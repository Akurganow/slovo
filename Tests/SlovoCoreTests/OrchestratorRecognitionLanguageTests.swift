import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The recognition language is SESSION state, not model state: the loaded model
// decodes any language, so a change must reach the next session's decoding options
// without a reload or a rebuilt pipeline. Driven through the real
// `WhisperKitTranscriber` over a `FakeSpeechEngine`, so the assertion sits on the
// session factory — the seam a fake transcriber cannot observe.
@Suite("Orchestrator recognition language")
struct OrchestratorRecognitionLanguageTests {
    private static func makeOrchestrator(transcriber: any Transcriber, cleaner: FakeCleaner) -> Orchestrator {
        PipelineFactory.makeOrchestrator(
            config: Config(),
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
                log: RedactionSafeLog(subsystem: "slovo", category: "recognition-language-test")
            )
        )
    }

    /// One dictation from key-down to injection (the `OrchestratorVocabularyBiasTests`
    /// shape: the readiness cue is awaited so a chunk reaches the session).
    private static func runDictation(on orchestrator: Orchestrator) async {
        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()
    }

    /// The configured language reaches the session the engine opens, so a dictation
    /// decodes what Settings says without the app telling the engine twice.
    /// Stated sensitivity: drop the `language:` argument from
    /// `WhisperKitTranscriber.begin`'s `makeSpeechStreamingSession` call and pass a
    /// literal (`.auto`) instead → the recorded language is `.auto` → RED.
    @Test
    func theConfiguredLanguageReachesTheSession() async {
        let engine = FakeSpeechEngine(finalize: .success("raw words"))
        let cleaner = FakeCleaner(outcome: .success("CLEANED"))
        let orchestrator = Self.makeOrchestrator(
            transcriber: TranscriberFixtures.makeTranscriber(engine: engine, language: .ru),
            cleaner: cleaner
        )

        await Self.runDictation(on: orchestrator)

        #expect(engine.sessionLanguages == [.ru],
                "the session must decode the configured recognition language")
    }

    /// A language change applies to the NEXT dictation through a live push — no
    /// pipeline rebuild, and no second model load: the same engine serves both
    /// sessions.
    /// Stated sensitivity: make `Orchestrator.updateRecognitionLanguage` a no-op, or
    /// bind the language at engine construction again (the shape that forced a
    /// rebuild) → the second session still records `.auto` → RED. Drop the push into
    /// the transcriber and the same assertion reddens.
    @Test
    func aPushedLanguageAppliesToTheNextDictationWithoutReloading() async {
        let engine = FakeSpeechEngine(finalize: .success("raw words"))
        let cleaner = FakeCleaner(outcome: .success("CLEANED"))
        let orchestrator = Self.makeOrchestrator(
            transcriber: TranscriberFixtures.makeTranscriber(engine: engine, keepWarmSeconds: nil),
            cleaner: cleaner
        )

        await Self.runDictation(on: orchestrator)
        await orchestrator.updateRecognitionLanguage(.ru)
        await Self.runDictation(on: orchestrator)

        #expect(engine.sessionLanguages == [.auto, .ru],
                "the pushed language must reach the next session, leaving the first one as it began")
        #expect(engine.loadCount == 1,
                "a language change must not reload the model: the loaded artifact decodes any language")
    }
}
