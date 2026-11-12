import Synchronization
import Testing

import SlovoTestSupport

@testable import SlovoCore

// One process, one speech model. The pipeline is rebuilt on a permission grant, on
// Retry Setup and on the hotkey retry; each rebuild asks the shared model for a
// fresh warm-up, and these pin what that warm-up must — and must not — start.
@Suite("Shared speech model")
struct SharedSpeechModelTests {
    /// Stands in for `Task.sleep`: records each duration it is asked for and returns at
    /// once, so no test sleeps. A call past `cap` records an issue and throws, which
    /// ends a loop that would otherwise never stop. `throwingAtCall` models a
    /// cancellation landing in that call: it records and throws `CancellationError`.
    private final class SleepRecorder: Sendable {
        private let recorded = Mutex<[Duration]>([])
        private let cap: Int
        private let throwingAtCall: Int?

        init(cap: Int = 20, throwingAtCall: Int? = nil) {
            self.cap = cap
            self.throwingAtCall = throwingAtCall
        }

        var durations: [Duration] { recorded.withLock { $0 } }

        func sleep(_ duration: Duration) async throws {
            let call = recorded.withLock { durations -> Int in
                durations.append(duration)
                return durations.count
            }
            if call > cap {
                Issue.record("the retry loop called sleep \(call) times, past the cap of \(cap)")
                throw CancellationError()
            }
            if call == throwingAtCall {
                throw CancellationError()
            }
        }
    }

    private static func makeModel(engine: FakeSpeechEngine, recorder: SleepRecorder) -> SharedSpeechModel {
        SharedSpeechModel(
            transcriber: TranscriberFixtures.makeTranscriber(engine: engine),
            sleep: { try await recorder.sleep($0) }
        )
    }

    /// A rebuild while the model is still loading gets its OWN warm-up task and
    /// joins the one load in flight. This is the first-run case: a Microphone or
    /// Accessibility grant lands in the middle of the download and used to start a
    /// second one against the same cache. The per-composition task is what the gate
    /// awaits, so it must be a task of this composition's own, not a shared one.
    /// Stated sensitivity: store one warm-up task on this type instead of minting one
    /// per composition → both compositions receive the same task → the identity
    /// assertion goes RED. Drop the single-flight join in
    /// `WhisperKitTranscriber.ensureModelLoaded` → the rebuild's warm-up parks a
    /// second gated load → loadCount == 2 → RED. A warm-up that never loads → no load
    /// parks → the bounded wait reports it → RED, with no hang. The neighbouring
    /// mutation — a transcriber built per composition — cannot be written against this
    /// test, which injects one; the guard in `AppDelegateHotkeyWiringSourceGuardTests`
    /// catches it.
    @Test
    func aRebuildDuringTheLoadJoinsTheOneLoadInFlight() async throws {
        let engine = FakeSpeechEngine()
        engine.gateLoad()
        let model = Self.makeModel(engine: engine, recorder: SleepRecorder())

        let launch = model.startWarmUp()
        let parked = await engine.waitForLoadSuspended()
        #expect(parked, "the launch's warm-up must park inside the load")
        let rebuild = model.startWarmUp()
        // A second load would park on the gate here; the correct path relents.
        await engine.waitForGatedLoadCountOrRelent(2)
        engine.releaseLoad()
        try await launch.value
        try await rebuild.value

        #expect(launch != rebuild, "every composition must preload through a warm-up task of its own")
        #expect(engine.loadCount == 1, "a rebuild mid-load must join that load, never start a second one")
    }

    /// A cancelled warm-up fails instead of completing: the sleep between attempts is
    /// where a cancel lands, its throw ends the task, and no further load starts. The
    /// gate that awaits the task opens only on success, so a cancelled warm-up never
    /// reports a model it did not load. The engine loads on its fourth attempt, so a
    /// loop that outlives the cancel ends there with a recorded count, not a hang.
    /// Stated sensitivity: swallow the sleep's error and keep looping → the fourth
    /// attempt loads, the task does not throw and loadCount is 4 → RED; end the task
    /// normally on a cancel → the task does not throw → RED.
    @Test
    func aCancelledWarmUpFailsAndMakesNoFurtherLoadAttempt() async {
        let engine = FakeSpeechEngine(loadFailuresBeforeSuccess: 3)
        let model = Self.makeModel(engine: engine, recorder: SleepRecorder(throwingAtCall: 1))
        let warmUp = model.startWarmUp()

        await #expect(throws: CancellationError.self) { try await warmUp.value }

        #expect(engine.loadCount == 1, "no load attempt follows the cancel")
        #expect(!engine.isLoaded)
    }

    /// A failed preload retries by itself until the model loads, so the gate that
    /// awaits the warm-up task opens only on a loaded model. The pauses are the
    /// durations the loop passes to the sleep, so the schedule is the loop's own.
    /// Stated sensitivity: stop after the first failed attempt → the task ends with
    /// loadCount 1 and no model → RED; a flat or a zero pause → the recorded durations
    /// differ → RED; keep looping after the load succeeds → the loop sleeps past the
    /// cap → RED.
    @Test
    func aFailedPreloadRetriesUntilTheModelLoads() async throws {
        let engine = FakeSpeechEngine(loadFailuresBeforeSuccess: 3)
        let recorder = SleepRecorder()
        let model = Self.makeModel(engine: engine, recorder: recorder)

        try await model.startWarmUp().value

        #expect(engine.loadCount == 4, "three failed attempts, then the one that loads")
        #expect(engine.isLoaded, "the task succeeds only on a loaded model")
        #expect(recorder.durations == [.seconds(1), .seconds(2), .seconds(4)])
    }

    /// The retry pauses double from one second and stop growing at sixty.
    /// Stated sensitivity: a schedule that does not grow, starts elsewhere or has no
    /// cap → the recorded durations differ → RED.
    @Test
    func retryPausesDoubleFromOneSecondUpToSixtySeconds() async throws {
        let engine = FakeSpeechEngine(loadFailuresBeforeSuccess: 8)
        let recorder = SleepRecorder()
        let model = Self.makeModel(engine: engine, recorder: recorder)

        try await model.startWarmUp().value

        #expect(recorder.durations == [1, 2, 4, 8, 16, 32, 60, 60].map { Duration.seconds($0) })
    }

    /// A load that fails for ever must never shift the pause out of range: only a pure
    /// call reaches a count that large, and a shift beyond the integer width is zero.
    /// Stated sensitivity: drop the cap on the shift → a zero pause → RED.
    @Test
    func theRetryPauseStaysAtSixtySecondsForAnyFailureCount() {
        #expect(SharedSpeechModel.retryPause(afterFailedAttempts: .max) == .seconds(60))
    }
}
