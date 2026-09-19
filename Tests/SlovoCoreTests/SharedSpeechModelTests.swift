import Testing

import SlovoCore
import SlovoTestSupport

// One process, one speech model. The pipeline is rebuilt on a permission grant, on
// Retry Setup and on the hotkey retry; each rebuild asks the shared model for a
// fresh warm-up, and these pin what that warm-up must — and must not — start.
@Suite("Shared speech model")
struct SharedSpeechModelTests {
    private static func makeModel(engine: FakeSpeechEngine) -> SharedSpeechModel {
        SharedSpeechModel(transcriber: TranscriberFixtures.makeTranscriber(engine: engine, keepWarmSeconds: nil))
    }

    /// A rebuild while the model is still loading gets its OWN warm-up task and
    /// joins the one load in flight. This is the first-run case: a Microphone or
    /// Accessibility grant lands in the middle of the download and used to start a
    /// second one against the same cache. The per-composition task is what the gate
    /// awaits, so it must be a task of this composition's own, not a shared one.
    /// Stated sensitivity: store one warm-up task on this type instead of minting one
    /// per composition → both compositions receive the same task → the identity
    /// assertion goes RED (and `aRebuildAfterAFailedPreloadRetriesTheLoad` shows what
    /// that costs). Drop the single-flight join in
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

    /// A rebuild after a FAILED preload must start a real retry — the path Retry
    /// Setup exists to serve after a first run with no network.
    /// Stated sensitivity: mint the warm-up once and store it (a `let warmUp: Task`
    /// on this type, shared by every composition) → the rebuild awaits the finished,
    /// already-failed task and never loads again → loadCount == 1 → RED.
    @Test
    func aRebuildAfterAFailedPreloadRetriesTheLoad() async {
        let engine = FakeSpeechEngine(loadFailuresBeforeSuccess: 1)
        let model = Self.makeModel(engine: engine)

        await model.startWarmUp().value
        await model.startWarmUp().value

        #expect(engine.loadCount == 2, "a rebuild after a failed preload must attempt the load again")
        #expect(engine.isLoaded, "the retry must leave the model resident")
    }
}
