import Synchronization
import Testing

import SlovoTestSupport

@testable import SlovoCore

// One process, one speech model. The pipeline is rebuilt on a permission grant, on
// Retry Setup and on the hotkey retry; each rebuild asks the shared model for a
// fresh warm-up, and these pin what that warm-up must — and must not — start.
@Suite("Shared speech model")
struct SharedSpeechModelTests {
    /// Records each failed-attempt count it is asked to pause for and returns at once,
    /// so no test sleeps.
    private final class PauseRecorder: Sendable {
        private let recorded = Mutex<[Int]>([])
        var failedAttempts: [Int] { recorded.withLock { $0 } }

        func pause(afterFailedAttempts attempts: Int) async {
            recorded.withLock { $0.append(attempts) }
        }
    }

    private static func makeModel(
        engine: FakeSpeechEngine,
        recorder: PauseRecorder = PauseRecorder()
    ) -> SharedSpeechModel {
        SharedSpeechModel(
            transcriber: TranscriberFixtures.makeTranscriber(engine: engine),
            pause: { await recorder.pause(afterFailedAttempts: $0) }
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
    /// second gated load → loadCount == 2 → RED. The neighbouring mutation — a
    /// transcriber built per composition — cannot be written against this test, which
    /// injects one; the guard in `AppDelegateHotkeyWiringSourceGuardTests` catches it.
    @Test
    func aRebuildDuringTheLoadJoinsTheOneLoadInFlight() async {
        let engine = FakeSpeechEngine()
        engine.gateLoad()
        let model = Self.makeModel(engine: engine)

        let launch = model.startWarmUp()
        await engine.waitForLoadSuspended()
        let rebuild = model.startWarmUp()
        // A second load would park on the gate here; the correct path relents.
        await engine.waitForGatedLoadCountOrRelent(2)
        engine.releaseLoad()
        await launch.value
        await rebuild.value

        #expect(launch != rebuild, "every composition must preload through a warm-up task of its own")
        #expect(engine.loadCount == 1, "a rebuild mid-load must join that load, never start a second one")
    }

    /// A failed preload retries by itself until the model loads, so the gate that
    /// awaits the warm-up task opens only on a loaded model.
    /// Stated sensitivity: stop after the first failed attempt (today's behaviour) →
    /// the task completes with loadCount 1 and no model → RED; pass a constant
    /// instead of the failure count → pauses differ → RED.
    @Test
    func aFailedPreloadRetriesUntilTheModelLoads() async {
        let engine = FakeSpeechEngine(loadFailuresBeforeSuccess: 3)
        let recorder = PauseRecorder()
        let model = Self.makeModel(engine: engine, recorder: recorder)

        await model.startWarmUp().value

        #expect(engine.loadCount == 4, "three failed attempts, then the one that loads")
        #expect(engine.isLoaded, "the task completes only on a loaded model")
        #expect(recorder.failedAttempts == [1, 2, 3], "each failure pauses with its own running count")
    }

    /// Stated sensitivity: a schedule that does not grow, starts elsewhere, or has no
    /// cap → RED; overflow on a large count → crash → RED.
    @Test
    func retryPausesDoubleFromOneSecondUpToSixtySeconds() {
        let schedule = (1...8).map { SharedSpeechModel.retryPause(afterFailedAttempts: $0) }

        #expect(schedule == [1, 2, 4, 8, 16, 32, 60, 60].map { Duration.seconds($0) })
        #expect(SharedSpeechModel.retryPause(afterFailedAttempts: .max) == .seconds(60))
    }
}
