import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Cleanup-off sessions skip the cleaner and hints entirely, inject the raw
// transcript, ignore a translate hold, and latch the flag at key-down so a
// mid-hold config push cannot split one session into half-raw, half-cleaned.
@Suite("Orchestrator cleanup toggle")
struct OrchestratorCleanupToggleTests {
    private static func deps(
        transcriber: any Transcriber,
        cleaner: FakeCleaner,
        injector: FakeInjector
    ) -> Dependencies {
        Dependencies(
            transcriber: transcriber, cleaner: cleaner, injector: injector,
            personalization: FakePersonalizationSource(terms: []),
            audio: FakeSystemAudioController(
                muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
            ),
            recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
            log: RedactionSafeLog(subsystem: "slovo", category: "toggle-test")
        )
    }

    private static func cleanupConfig(runsCleaner: Bool) -> CleanupConfig {
        var cleanupConfig = Config().cleanupConfig
        cleanupConfig.runsCleaner = runsCleaner
        return cleanupConfig
    }

    /// Stated sensitivity: remove the `sessionRunsCleaner` guard in
    /// `cleanAndContinue` → the cleaner records a call and "CLEANED" is
    /// injected → RED on both expectations.
    @Test
    func offSkipsCleanerAndInjectsRaw() async {
        let cleaner = FakeCleaner(outcome: .success("CLEANED"))
        let injector = FakeInjector(outcome: .success)
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(transcriber: FakeTranscriber(outcome: .success("raw words")), cleaner: cleaner, injector: injector),
            cleanupConfig: Self.cleanupConfig(runsCleaner: false)
        )

        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()

        #expect(cleaner.calls.isEmpty, "cleanup-off must never call the cleaner")
        #expect(injector.calls.last == "raw words")
    }

    /// Stated sensitivity: route the translate mode around the guard (e.g. run
    /// the cleaner whenever `sessionMode == .translate`) → RED.
    @Test
    func offIgnoresTranslateHold() async {
        let cleaner = FakeCleaner(outcome: .success("TRANSLATED"))
        let injector = FakeInjector(outcome: .success)
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(transcriber: FakeTranscriber(outcome: .success("сырой текст")), cleaner: cleaner, injector: injector),
            cleanupConfig: Self.cleanupConfig(runsCleaner: false)
        )

        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.stopRequested(.translate))
        await orchestrator.awaitPipelineDrain()

        #expect(cleaner.calls.isEmpty, "a translate hold with cleanup off must stay raw")
        #expect(injector.calls.last == "сырой текст")
    }

    /// Stated sensitivity: read `cleanupConfig.runsCleaner` directly in
    /// `cleanAndContinue` instead of the `.beginCapture` latch → the mid-hold
    /// push flips the in-flight session → RED.
    @Test
    func midHoldPushToOffStillCleansTheLatchedSession() async {
        let cleaner = FakeCleaner(outcome: .success("CLEANED"))
        let injector = FakeInjector(outcome: .success)
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(transcriber: FakeTranscriber(outcome: .success("raw")), cleaner: cleaner, injector: injector)
        )

        await orchestrator.handle(.startRequested)
        await orchestrator.updateCleanupConfig(Self.cleanupConfig(runsCleaner: false))
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()

        #expect(cleaner.calls.count == 1, "the session latched ON at key-down must still clean")
        #expect(injector.calls.last == "CLEANED")
    }

    /// Stated sensitivity: same mutation as above, opposite direction — a
    /// session latched OFF must stay raw even if the push turns cleanup on
    /// mid-hold → RED.
    @Test
    func midHoldPushToOnStaysRawForTheLatchedSession() async {
        let cleaner = FakeCleaner(outcome: .success("CLEANED"))
        let injector = FakeInjector(outcome: .success)
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(transcriber: FakeTranscriber(outcome: .success("raw")), cleaner: cleaner, injector: injector),
            cleanupConfig: Self.cleanupConfig(runsCleaner: false)
        )

        await orchestrator.handle(.startRequested)
        await orchestrator.updateCleanupConfig(Self.cleanupConfig(runsCleaner: true))
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()

        #expect(cleaner.calls.isEmpty)
        #expect(injector.calls.last == "raw")
    }
}
