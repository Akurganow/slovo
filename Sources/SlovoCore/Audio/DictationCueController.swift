import AudioToolbox
import Foundation
import Synchronization

/// One audible boundary in a dictation session.
public enum DictationCue: Equatable, Hashable, Sendable {
    case start
    case end
    case error
}

/// A cue's place in the queue, claimed synchronously so cue order never depends on
/// task scheduling.
public struct DictationCuePlayback: Sendable {
    private let playback: Task<Void, Never>?

    internal init(playback: Task<Void, Never>?) {
        self.playback = playback
    }

    /// A cue that will not be heard.
    public static var inaudible: DictationCuePlayback {
        DictationCuePlayback(playback: nil)
    }

    /// An audible cue that already finished, for doubles with instant playback.
    public static var completed: DictationCuePlayback {
        DictationCuePlayback(playback: Task {})
    }

    public func awaitCompletion() async {
        await playback?.value
    }
}

/// Session-scoped playback for dictation feedback. No method here may gate a
/// dictation step — `beginPlayback` claims the slot synchronously and reports
/// completion through its handle.
public protocol DictationCueController: AnyObject, Sendable {
    func updateEnabled(_ isEnabled: Bool)
    func beginSession()
    func beginPlayback(_ cue: DictationCue) -> DictationCuePlayback
    func enqueue(_ cue: DictationCue)
    func endSession()
}

/// Serializes every cue through one FIFO and snapshots the enabled preference at
/// dictation start.
public final class AudioServicesDictationCueController: DictationCueController, @unchecked Sendable {
    internal typealias Playback = @Sendable (DictationCue) async throws -> Void

    /// Longest a single cue may hold the FIFO. Well above the bundled cues (~0.25 s),
    /// so it fires only when playback never reports completion.
    internal static let defaultPlaybackDeadline = Duration.seconds(3)

    private struct State {
        var configuredEnabled: Bool
        var isSessionActive = false
        var sessionEnabled = false
        var tail: Task<Void, Never>?
    }

    private let lock = NSLock()
    private let log: RedactionSafeLog
    private let playback: Playback
    private let playbackDeadline: Duration
    private var state: State

    public convenience init(isEnabled: Bool, log: RedactionSafeLog) {
        let player = AudioServicesAlertCuePlayer(log: log)
        self.init(isEnabled: isEnabled, log: log) { cue in
            try await player.playToCompletion(cue)
        }
    }

    internal init(
        isEnabled: Bool,
        log: RedactionSafeLog,
        playbackDeadline: Duration = AudioServicesDictationCueController.defaultPlaybackDeadline,
        playback: @escaping Playback
    ) {
        self.log = log
        self.playback = playback
        self.playbackDeadline = playbackDeadline
        self.state = State(configuredEnabled: isEnabled)
    }

    public func updateEnabled(_ isEnabled: Bool) {
        lock.withLock { state.configuredEnabled = isEnabled }
    }

    public func beginSession() {
        lock.withLock {
            state.isSessionActive = true
            state.sessionEnabled = state.configuredEnabled
        }
    }

    public func beginPlayback(_ cue: DictationCue) -> DictationCuePlayback {
        DictationCuePlayback(playback: schedule(cue))
    }

    public func enqueue(_ cue: DictationCue) {
        _ = schedule(cue)
    }

    /// Ends the session and detaches the FIFO tail, so the next dictation's cue never
    /// queues behind this one's. A cue already playing still finishes.
    public func endSession() {
        lock.withLock {
            state.isSessionActive = false
            state.tail = nil
        }
    }

    private func schedule(_ cue: DictationCue) -> Task<Void, Never>? {
        lock.withLock {
            guard state.isSessionActive, state.sessionEnabled else { return nil }
            let previous = state.tail
            let playback = self.playback
            let deadline = self.playbackDeadline
            let log = self.log
            let task = Task {
                await previous?.value
                await Self.play(cue, using: playback, deadline: deadline, log: log)
            }
            state.tail = task
            return task
        }
    }

    /// Returns on playback or the deadline, whichever lands first, so a cue that never
    /// completes strands neither the FIFO nor its caller.
    private static func play(
        _ cue: DictationCue,
        using playback: @escaping Playback,
        deadline: Duration,
        log: RedactionSafeLog
    ) async {
        await withCheckedContinuation { continuation in
            let resumeOnce = OneShotAction { continuation.resume() }
            let deadlineTask = Task {
                try? await Task.sleep(for: deadline)
                if resumeOnce.run() {
                    log.event("dictation cue playback deadline elapsed")
                }
            }
            Task {
                do {
                    try await playback(cue)
                } catch {
                    log.event("dictation cue playback failed")
                }
                resumeOnce.run()
                // Otherwise every cue leaves a task sleeping until the deadline.
                deadlineTask.cancel()
            }
        }
    }
}

/// Resolves and retains bundled `SystemSoundID`s, then plays them through the
/// public macOS alert channel so the system owns cue loudness and accessibility
/// behavior.
internal final class AudioServicesAlertCuePlayer: @unchecked Sendable {
    private enum PlaybackError: Error {
        case soundUnavailable
    }

    private let log: RedactionSafeLog
    private let soundIDs: [DictationCue: SystemSoundID]

    /// The cues resolved from the bundle at init, so a test can prove the runtime
    /// lookup still finds every one — a packaging mistake otherwise ships silence.
    internal var resolvedCues: Set<DictationCue> { Set(soundIDs.keys) }

    internal init(log: RedactionSafeLog) {
        self.log = log
        self.soundIDs = Dictionary(
            uniqueKeysWithValues: DictationCue.allCases.compactMap { cue in
                Self.loadSoundID(for: cue).map { (cue, $0) }
            }
        )
    }

    deinit {
        for soundID in soundIDs.values where AudioServicesDisposeSystemSoundID(soundID) != noErr {
            log.event("dictation cue sound disposal failed")
        }
    }

    internal func playToCompletion(_ cue: DictationCue) async throws {
        let soundID = try soundID(for: cue)
        await withCheckedContinuation { continuation in
            AudioServicesPlayAlertSoundWithCompletion(soundID) {
                continuation.resume()
            }
        }
    }

    private func soundID(for cue: DictationCue) throws -> SystemSoundID {
        guard let soundID = soundIDs[cue] else { throw PlaybackError.soundUnavailable }
        return soundID
    }

    private static func loadSoundID(for cue: DictationCue) -> SystemSoundID? {
        guard let url = SlovoCoreResourceBundle.resolve()?.url(
            forResource: cue.resourceName,
            withExtension: "wav",
            subdirectory: "AudioCues"
        ) else {
            return nil
        }

        var created = SystemSoundID()
        guard AudioServicesCreateSystemSoundID(url as CFURL, &created) == noErr else {
            return nil
        }
        return created
    }
}

private extension DictationCue {
    static let allCases: [DictationCue] = [.start, .end, .error]

    var resourceName: String {
        switch self {
        case .start: "start"
        case .end: "end"
        case .error: "error"
        }
    }
}

/// Performs its action for the first caller only, so racing branches cannot resume
/// one continuation twice.
internal final class OneShotAction: Sendable {
    private let hasRun = Atomic(false)
    private let action: @Sendable () -> Void

    internal init(_ action: @escaping @Sendable () -> Void) {
        self.action = action
    }

    /// True for the single caller that ran the action.
    @discardableResult
    internal func run() -> Bool {
        let (exchanged, _) = hasRun.compareExchange(
            expected: false,
            desired: true,
            ordering: .acquiringAndReleasing
        )
        if exchanged { action() }
        return exchanged
    }
}
