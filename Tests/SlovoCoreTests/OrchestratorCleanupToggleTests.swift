import Foundation
import Testing

@testable import SlovoCore
import SlovoTestSupport

// Cleanup-off sessions skip the cleaner and hints entirely, inject the raw
// transcript, and ignore a translate hold.
@Suite("Orchestrator cleanup toggle")
struct OrchestratorCleanupToggleTests {
    private static func deps(
        transcriber: any Transcriber,
        cleaner: FakeCleaner,
        injector: FakeInjector,
        settings: DictationSettings
    ) -> Dependencies {
        Dependencies(
            transcriber: transcriber, cleaner: cleaner, injector: injector,
            personalization: FakePersonalizationSource(terms: []),
            audio: FakeSystemAudioController(
                muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
            ),
            recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
            cueController: FakeDictationCueController(),
            log: RedactionSafeLog(subsystem: "slovo", category: "toggle-test"),
            settings: FakeSettingsSource(settings).provider
        )
    }

    /// Stated sensitivity: route the translate mode around the guard (e.g. run
    /// the cleaner whenever `sessionMode == .translate`) → RED.
    @Test
    func offIgnoresTranslateHold() async {
        let cleaner = FakeCleaner(outcome: .success("TRANSLATED"))
        let injector = FakeInjector(outcome: .success)
        let rawMode = AppState(config: Config(cleanupEnabled: false), isOpenRouterKeyPresent: true).dictationSettings
        let orchestrator = PipelineFactory.makeOrchestrator(
            dependencies: Self.deps(
                transcriber: FakeTranscriber(outcome: .success("сырой текст")),
                cleaner: cleaner,
                injector: injector,
                settings: rawMode
            )
        )

        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.stopRequested(.translate))
        await orchestrator.awaitPipelineDrain()

        #expect(cleaner.calls.isEmpty, "a translate hold with cleanup off must stay raw")
        #expect(injector.calls.last == "сырой текст")
    }
}
