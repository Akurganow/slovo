import Synchronization
import Testing

@testable import SlovoCore

// One FIFO, one enabled snapshot per dictation. `beginPlayback` claims its slot
// before returning, so cue order follows call order, not task scheduling.
@Suite("AudioServices dictation cue controller")
struct AudioServicesDictationCueControllerTests {
    /// Sensitivity: a slot claimed inside a Task lets the later End cue reach the
    /// queue first. One trial misses that race too often to be a detector.
    @Test
    func beginPlaybackClaimsItsQueueSlotSynchronously() async {
        for _ in 0 ..< Self.claimOrderTrials {
            let playback = PlaybackProbe()
            let controller = Self.controller(playback: playback)
            controller.beginSession()

            let start = controller.beginPlayback(.start)
            controller.enqueue(.end)

            await start.awaitCompletion()
            #expect(await playback.waitForCallCount(2))
            #expect(await playback.calls == [.start, .end],
                    "the cue whose slot was claimed first must play first")
            controller.endSession()
        }
    }

    /// Sensitivity: scheduling a cue outside a session plays it; a handle that never
    /// resolves hangs the awaiting caller.
    @Test
    func cuesClaimedOutsideASessionNeverReachPlayback() async {
        let playback = PlaybackProbe()
        let controller = Self.controller(playback: playback)

        controller.beginSession()
        await controller.beginPlayback(.start).awaitCompletion()
        controller.endSession()

        await controller.beginPlayback(.end).awaitCompletion()

        #expect(await playback.calls == [.start], "only the in-session cue may reach playback")
    }

    /// Sensitivity: independent dispatch lets Error overtake a blocked End.
    @Test
    func queuedEndAndErrorUseOneFifo() async {
        let playback = PlaybackProbe(blocksSuccessfulCalls: true)
        let controller = Self.controller(playback: playback)
        controller.beginSession()

        controller.enqueue(.end)
        controller.enqueue(.error)

        await playback.waitForCallCount(1)
        #expect(await playback.calls == [.end], "Error must not overtake a blocked End cue")
        #expect(await playback.releaseNext())
        await playback.waitForCallCount(2)
        #expect(await playback.calls == [.end, .error])
        #expect(await playback.releaseNext())
    }

    /// Sensitivity: unchained scheduling lets Start play during End. The window bounds
    /// a negative observation; it never substitutes for synchronization.
    @Test
    func startJoinsTheSingleFifoBehindAnEarlierCue() async {
        let playback = PlaybackProbe(blocksSuccessfulCalls: true)
        let controller = Self.controller(playback: playback)
        controller.beginSession()
        controller.enqueue(.end)
        await playback.waitForCallCount(1)

        let start = controller.beginPlayback(.start)
        let startOvertookEnd = await playback.waitForCallCount(2, within: Self.negativeObservationWindow)
        #expect(!startOvertookEnd, "Start must not enter playback while the earlier End cue is still playing")

        #expect(await playback.releaseNext())
        #expect(await playback.waitForCallCount(2), "Start must play once End releases the queue")
        #expect(await playback.calls == [.end, .start])
        #expect(await playback.releaseNext())
        await start.awaitCompletion()
    }

    /// Sensitivity: a handle resolving without awaiting its task frees the caller mid-cue.
    @Test
    func awaitCompletionReturnsOnlyAfterItsOwnPlaybackFinishes() async {
        let playback = PlaybackProbe(blocksSuccessfulCalls: true)
        let controller = Self.controller(playback: playback)
        controller.beginSession()

        let start = controller.beginPlayback(.start)
        let caller = CallReturnProbe()
        Task {
            await start.awaitCompletion()
            await caller.note()
        }
        await playback.waitForCallCount(1)

        let returnedDuringPlayback = await caller.waitForReturn(within: Self.negativeObservationWindow)
        #expect(!returnedDuringPlayback, "the caller must keep waiting while its own cue is still playing")

        #expect(await playback.releaseNext())
        #expect(await caller.waitForReturn(), "the caller must return once its own cue finishes")
    }

    /// Sensitivity: keeping the tail across `endSession()` chains the next session's
    /// cue behind the previous one's.
    @Test
    func endSessionDetachesTheTailSoTheNextSessionIsNotDelayed() async {
        let playback = PlaybackProbe(blocksSuccessfulCalls: true)
        let controller = Self.controller(playback: playback)

        controller.beginSession()
        controller.enqueue(.end)
        await playback.waitForCallCount(1)
        controller.endSession()

        controller.beginSession()
        controller.enqueue(.start)

        #expect(await playback.waitForCallCount(2),
                "a new session's cue must not wait behind the previous session's playback")
        #expect(await playback.calls == [.end, .start])
        #expect(await playback.releaseNext())
        #expect(await playback.releaseNext())
    }

    /// Sensitivity: without the deadline race a cue that never completes holds the FIFO
    /// and its caller forever.
    @Test
    func playbackThatNeverCompletesIsReleasedAtTheDeadline() async {
        let playback = PlaybackProbe(blocksSuccessfulCalls: true)
        let controller = Self.controller(playback: playback, playbackDeadline: .milliseconds(20))
        controller.beginSession()

        let start = controller.beginPlayback(.start)
        let caller = CallReturnProbe()
        Task {
            await start.awaitCompletion()
            await caller.note()
        }
        await playback.waitForCallCount(1)
        controller.enqueue(.end)

        #expect(await caller.waitForReturn(), "the deadline must release a caller whose cue never completes")
        #expect(await playback.waitForCallCount(2), "the deadline must free the FIFO for the following cue")
        #expect(await playback.calls == [.start, .end])

        #expect(await playback.releaseNext())
        #expect(await playback.releaseNext())
    }

    /// Sensitivity: with no guard both branches resume one continuation and the process
    /// traps. Aligned waits collide them; a non-atomic guard still slips through.
    @Test
    func playbackCompletionAndDeadlineResumeTheCallerOnlyOnce() async {
        await withTaskGroup(of: Void.self) { races in
            for _ in 0 ..< Self.resumeRaceIterations {
                races.addTask {
                    let playback = PlaybackProbe(playbackDelay: Self.resumeRaceWait)
                    let controller = Self.controller(playback: playback, playbackDeadline: Self.resumeRaceWait)
                    controller.beginSession()
                    await controller.beginPlayback(.start).awaitCompletion()
                    // Whichever branch releases the caller, playback itself still runs;
                    // the double-resume this pins would trap the process, not fail here.
                    #expect(await playback.waitForCallCount(1), "the cue must still reach playback")
                }
            }
        }
    }

    /// Sensitivity: a guard that loads before it stores lets more than one caller
    /// through. A shared release instant frees every caller within nanoseconds of the
    /// others, which the deadline-versus-playback race cannot do.
    @Test
    func oneShotActionRunsForExactlyOneOfManySimultaneousCallers() async {
        for _ in 0 ..< Self.oneShotTrials {
            let runs = Atomic(0)
            let action = OneShotAction { runs.wrappingAdd(1, ordering: .sequentiallyConsistent) }
            let releaseAt = ContinuousClock.now.advanced(by: Self.oneShotGateWait)

            let winners = await withTaskGroup(of: Bool.self) { callers in
                for _ in 0 ..< Self.oneShotCallers {
                    callers.addTask {
                        while ContinuousClock.now < releaseAt {}
                        return action.run()
                    }
                }
                return await callers.reduce(0) { $0 + ($1 ? 1 : 0) }
            }

            #expect(winners == 1, "exactly one caller may win the one-shot")
            #expect(runs.load(ordering: .sequentiallyConsistent) == 1, "the action must run exactly once")
        }
    }

    /// Sensitivity: reading the live preference instead of the session snapshot either
    /// suppresses the current Start or plays the next one.
    @Test
    func enabledUpdateAppliesToTheNextSessionOnly() async {
        let playback = PlaybackProbe()
        let controller = Self.controller(isEnabled: true, playback: playback)

        controller.beginSession()
        controller.updateEnabled(false)
        await controller.beginPlayback(.start).awaitCompletion()
        controller.endSession()

        controller.beginSession()
        await controller.beginPlayback(.start).awaitCompletion()
        controller.endSession()

        #expect(await playback.calls == [.start],
                "the current session keeps its enabled snapshot; the next session sees the update")
    }

    /// Sensitivity: ignoring the session snapshot records the cue.
    @Test
    func disabledStartPerformsNoPlayback() async {
        let playback = PlaybackProbe()
        let controller = Self.controller(isEnabled: false, playback: playback)
        controller.beginSession()

        await controller.beginPlayback(.start).awaitCompletion()

        #expect(await playback.calls.isEmpty, "disabled cues must not enter the playback queue")
    }

    /// Sensitivity: propagating the error breaks the nonthrowing contract; terminating
    /// the queue drops the following cue.
    @Test
    func playbackFailureIsContainedAndTheQueueContinues() async {
        let playback = PlaybackProbe(failingCallIndexes: [1])
        let logs = Mutex<[String]>([])
        let controller = AudioServicesDictationCueController(
            isEnabled: true,
            log: RedactionSafeLog(subsystem: "slovo", category: "cue-controller-test") { message in
                logs.withLock { $0.append(message) }
            },
            playback: { cue in try await playback.play(cue) }
        )
        controller.beginSession()

        controller.enqueue(.end)
        await controller.beginPlayback(.error).awaitCompletion()

        #expect(await playback.calls == [.end, .error],
                "a failed cue must be logged and skipped without poisoning the FIFO")
        #expect(logs.withLock { $0 }.count == 1, "one failed playback must produce one payload-free diagnostic")
        #expect(!logs.withLock { $0 }.joined().contains("ScriptedFailure"), "the wrapped error payload must not be logged")
    }

    /// A lost ordering shows far sooner than this; passing runs never wait it out.
    private static let negativeObservationWindow = Duration.milliseconds(50)

    /// Each race is one chance at the resume window; they run concurrently.
    private static let resumeRaceIterations = 400

    /// Both branches wait this span so they wake together.
    private static let resumeRaceWait = Duration.milliseconds(1)

    /// Callers spin to a shared instant, so every thread the pool gave them leaves the
    /// gate together rather than within a timer's jitter. Under a loaded pool a trial
    /// may get too few threads to race at all, so trials are many.
    private static let oneShotCallers = 16
    private static let oneShotTrials = 250
    private static let oneShotGateWait = Duration.milliseconds(2)

    /// A single trial misses a deferred claim about one run in ten.
    private static let claimOrderTrials = 20

    private static func controller(
        isEnabled: Bool = true,
        playback: PlaybackProbe,
        playbackDeadline: Duration = AudioServicesDictationCueController.defaultPlaybackDeadline
    ) -> AudioServicesDictationCueController {
        AudioServicesDictationCueController(
            isEnabled: isEnabled,
            log: RedactionSafeLog(subsystem: "slovo", category: "cue-controller-test"),
            playbackDeadline: playbackDeadline,
            playback: { cue in try await playback.play(cue) }
        )
    }
}

private actor PlaybackProbe {
    struct ScriptedFailure: Error {}

    private(set) var calls: [DictationCue] = []
    private var callCountWaiters: [Waiter] = []
    private var playbackWaiters: [CheckedContinuation<Void, Never>] = []
    private var nextWaiterID = 0
    private let blocksSuccessfulCalls: Bool
    private let failingCallIndexes: Set<Int>
    private let playbackDelay: Duration?

    private struct Waiter {
        let id: Int
        let threshold: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    init(
        blocksSuccessfulCalls: Bool = false,
        failingCallIndexes: Set<Int> = [],
        playbackDelay: Duration? = nil
    ) {
        self.blocksSuccessfulCalls = blocksSuccessfulCalls
        self.failingCallIndexes = failingCallIndexes
        self.playbackDelay = playbackDelay
    }

    func play(_ cue: DictationCue) async throws {
        if let playbackDelay { try? await Task.sleep(for: playbackDelay) }
        let callIndex = calls.count + 1
        if failingCallIndexes.contains(callIndex) {
            record(cue)
            throw ScriptedFailure()
        }
        guard blocksSuccessfulCalls else {
            record(cue)
            return
        }
        await withCheckedContinuation { continuation in
            playbackWaiters.append(continuation)
            record(cue)
        }
    }

    /// Bounded so a stalled controller fails the test instead of hanging the suite.
    @discardableResult
    func waitForCallCount(_ count: Int, within timeout: Duration = .seconds(2)) async -> Bool {
        guard calls.count < count else { return true }
        let id = nextWaiterID
        nextWaiterID += 1
        let expiry = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.expire(id)
        }
        await withCheckedContinuation { continuation in
            callCountWaiters.append(Waiter(id: id, threshold: count, continuation: continuation))
        }
        expiry.cancel()
        return calls.count >= count
    }

    func releaseNext() -> Bool {
        guard !playbackWaiters.isEmpty else { return false }
        playbackWaiters.removeFirst().resume()
        return true
    }

    private func expire(_ id: Int) {
        guard let index = callCountWaiters.firstIndex(where: { $0.id == id }) else { return }
        callCountWaiters.remove(at: index).continuation.resume()
    }

    private func record(_ cue: DictationCue) {
        calls.append(cue)
        let ready = callCountWaiters.filter { calls.count >= $0.threshold }
        callCountWaiters.removeAll { calls.count >= $0.threshold }
        ready.forEach { $0.continuation.resume() }
    }
}

/// Records that an awaited handle resolved, so a test can bound that wait.
private actor CallReturnProbe {
    private var hasReturned = false
    private var waiter: CheckedContinuation<Void, Never>?

    func note() {
        hasReturned = true
        waiter?.resume()
        waiter = nil
    }

    func waitForReturn(within timeout: Duration = .seconds(2)) async -> Bool {
        guard !hasReturned else { return true }
        let expiry = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.expire()
        }
        await withCheckedContinuation { continuation in
            waiter = continuation
        }
        expiry.cancel()
        return hasReturned
    }

    private func expire() {
        waiter?.resume()
        waiter = nil
    }
}
