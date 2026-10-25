import AudioToolbox
import Foundation
import os
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

/// One fact in a cue's playback history. The set is closed and holds no text, so a
/// log line built from it cannot carry user data.
///
/// `elapsedMs` counts from the moment `play` hands the cue to the system, so it
/// excludes the wait behind earlier cues. It is whole milliseconds on `ContinuousClock`
/// and a diagnostic only: no rule or test depends on its value.
internal enum CuePlaybackEvent: Equatable, Sendable {
    case requested(DictationCue)
    case completed(DictationCue, elapsedMs: Int)
    case deadlineElapsed(DictationCue)
    case late(DictationCue, elapsedMs: Int)
    case failed(DictationCue)
}

/// Serializes every cue through one FIFO and snapshots the enabled preference at
/// dictation start.
public final class AudioServicesDictationCueController: DictationCueController, @unchecked Sendable {
    internal typealias Playback = @Sendable (DictationCue) async throws -> Void
    internal typealias Report = @Sendable (CuePlaybackEvent) -> Void

    private static let diagnosticLog = Logger(subsystem: "com.slovo.app", category: "dictation")

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
    private let report: Report
    private let playback: Playback
    private let playbackDeadline: Duration
    private var state: State

    public convenience init(isEnabled: Bool) {
        let player = AudioServicesAlertCuePlayer()
        self.init(isEnabled: isEnabled, report: Self.writeToLog) { cue in
            try await player.playToCompletion(cue)
        }
    }

    /// `report` has no default, so a test must say what happens to events and never
    /// writes cue lines to the real log by omission.
    internal init(
        isEnabled: Bool,
        report: @escaping Report,
        playbackDeadline: Duration = AudioServicesDictationCueController.defaultPlaybackDeadline,
        playback: @escaping Playback
    ) {
        self.report = report
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
            let report = self.report
            let task = Task {
                await previous?.value
                await Self.play(cue, using: playback, deadline: deadline, report: report)
            }
            state.tail = task
            return task
        }
    }

    /// Returns on playback or the deadline, whichever lands first, so a cue that never
    /// completes strands neither the FIFO nor its caller.
    ///
    /// The winner's event is the continuation's value and is reported here, before the
    /// FIFO moves on, so a cue's terminal event always precedes the next cue's request.
    private static func play(
        _ cue: DictationCue,
        using playback: @escaping Playback,
        deadline: Duration,
        report: @escaping Report
    ) async {
        let startedAt = ContinuousClock.now
        report(.requested(cue))
        let terminal = await withCheckedContinuation { (continuation: CheckedContinuation<CuePlaybackEvent, Never>) in
            let resumeOnce = OneShotAction<CuePlaybackEvent> { continuation.resume(returning: $0) }
            let deadlineTask = Task {
                try? await Task.sleep(for: deadline)
                resumeOnce.run(.deadlineElapsed(cue))
            }
            Task {
                do {
                    try await playback(cue)
                    let elapsedMs = Int(startedAt.duration(to: .now) / .milliseconds(1))
                    if !resumeOnce.run(.completed(cue, elapsedMs: elapsedMs)) {
                        report(.late(cue, elapsedMs: elapsedMs))
                    }
                } catch {
                    resumeOnce.run(.failed(cue))
                }
                // Otherwise every cue leaves a task sleeping until the deadline.
                deadlineTask.cancel()
            }
        }
        report(terminal)
    }

    /// One fixed literal per event: the exhaustive switch means a new event cannot
    /// ship without its own line.
    private static func writeToLog(_ event: CuePlaybackEvent) {
        switch event {
        case .requested(let cue):
            diagnosticLog.log("cue.requested cue=\(cue.resourceName, privacy: .public)")
        case .completed(let cue, let elapsedMs):
            diagnosticLog.log("cue.completed cue=\(cue.resourceName, privacy: .public) ms=\(elapsedMs, privacy: .public)")
        case .deadlineElapsed(let cue):
            diagnosticLog.error("cue.deadlineElapsed cue=\(cue.resourceName, privacy: .public)")
        case .late(let cue, let elapsedMs):
            diagnosticLog.log("cue.late cue=\(cue.resourceName, privacy: .public) ms=\(elapsedMs, privacy: .public)")
        case .failed(let cue):
            diagnosticLog.error("cue.failed cue=\(cue.resourceName, privacy: .public)")
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

    private let soundIDs: [DictationCue: SystemSoundID]

    /// The cues resolved from the bundle at init, so a test can prove the runtime
    /// lookup still finds every one — a packaging mistake otherwise ships silence.
    internal var resolvedCues: Set<DictationCue> { Set(soundIDs.keys) }

    internal init() {
        self.soundIDs = Dictionary(
            uniqueKeysWithValues: DictationCue.allCases.compactMap { cue in
                Self.loadSoundID(for: cue).map { (cue, $0) }
            }
        )
    }

    deinit {
        for soundID in soundIDs.values {
            AudioServicesDisposeSystemSoundID(soundID)
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
internal final class OneShotAction<Value: Sendable>: Sendable {
    private let hasRun = Atomic(false)
    private let action: @Sendable (Value) -> Void

    internal init(_ action: @escaping @Sendable (Value) -> Void) {
        self.action = action
    }

    /// Hands `value` to the action for the single winning caller and returns true for
    /// it. A losing caller's value is dropped.
    @discardableResult
    internal func run(_ value: Value) -> Bool {
        let (exchanged, _) = hasRun.compareExchange(
            expected: false,
            desired: true,
            ordering: .acquiringAndReleasing
        )
        if exchanged { action(value) }
        return exchanged
    }
}
