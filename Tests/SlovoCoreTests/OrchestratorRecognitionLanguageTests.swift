import Foundation
import Testing

@testable import SlovoCore
import SlovoTestSupport

// The recognition language is SESSION state, not model state: the loaded model
// decodes any language, so each dictation hands its session the language it read,
// with no reload or rebuilt pipeline. Driven through the real
// `WhisperKitTranscriber` over a `FakeSpeechEngine`, so the assertion sits on the
// session factory — the seam a fake transcriber cannot observe.
@Suite("Orchestrator recognition language")
struct OrchestratorRecognitionLanguageTests {
    private static func settings(language: Language) -> DictationSettings {
        AppState(config: Config(language: language), isOpenRouterKeyPresent: true).dictationSettings
    }

    private static func makeOrchestrator(
        transcriber: any Transcriber,
        cleaner: FakeCleaner,
        settings: FakeSettingsSource
    ) -> Orchestrator {
        PipelineFactory.makeOrchestrator(
            dependencies: Dependencies(
                transcriber: transcriber,
                cleaner: cleaner,
                injector: FakeInjector(outcome: .success),
                personalization: FakePersonalizationSource(terms: []),
                audio: FakeSystemAudioController(
                    muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
                ),
                recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
                cueController: FakeDictationCueController(),
                log: RedactionSafeLog(subsystem: "slovo", category: "recognition-language-test"),
                settings: settings.provider
            )
        )
    }

    /// One dictation from key-down to injection.
    private static func runDictation(on orchestrator: Orchestrator) async {
        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()
    }

    /// The language the dictation read reaches the session the engine opens, so a
    /// dictation decodes what Settings says.
    /// Stated sensitivity: drop the `language:` argument from
    /// `WhisperKitTranscriber.begin`'s `makeSpeechStreamingSession` call and pass a
    /// literal (`.auto`) instead, or have the orchestrator pass `.auto` to `begin`
    /// → the recorded language is `.auto` → RED.
    @Test
    func theConfiguredLanguageReachesTheSession() async {
        let engine = FakeSpeechEngine(finalize: .success("raw words"))
        let cleaner = FakeCleaner(outcome: .success("CLEANED"))
        let orchestrator = Self.makeOrchestrator(
            transcriber: TranscriberFixtures.makeTranscriber(engine: engine),
            cleaner: cleaner,
            settings: FakeSettingsSource(Self.settings(language: .ru))
        )

        await Self.runDictation(on: orchestrator)

        #expect(engine.sessionLanguages == [.ru],
                "the session must decode the configured recognition language")
    }

    /// A language change applies to the NEXT dictation — no pipeline rebuild, and no
    /// second model load: the same engine serves both sessions.
    /// Stated sensitivity: have `begin` ignore its `language` argument and keep the
    /// first one → the second session still records `.auto` → RED. `begin` calls
    /// `engine.load()` unconditionally → `loadCount` 3 → RED.
    @Test
    func aChangedLanguageAppliesToTheNextDictationWithoutReloading() async throws {
        let engine = FakeSpeechEngine(finalize: .success("raw words"))
        let cleaner = FakeCleaner(outcome: .success("CLEANED"))
        let transcriber = TranscriberFixtures.makeTranscriber(engine: engine)
        let settings = FakeSettingsSource(Self.settings(language: .auto))
        let orchestrator = Self.makeOrchestrator(transcriber: transcriber, cleaner: cleaner, settings: settings)

        try await transcriber.warmUp()
        await Self.runDictation(on: orchestrator)
        settings.replace(with: Self.settings(language: .ru))
        await Self.runDictation(on: orchestrator)

        #expect(engine.sessionLanguages == [.auto, .ru],
                "the changed language must reach the next session, leaving the first one as it began")
        #expect(engine.loadCount == 1,
                "a language change must not reload the model: the loaded artifact decodes any language")
    }
}
