import Foundation
import Testing

@testable import SlovoCore
import SlovoTestSupport

// The experimental switch gates ONLY what reaches the speech engine; the cleaner's
// personalization context carries the full vocabulary either way. Driven through
// the real `WhisperKitTranscriber` over a `FakeSpeechEngine`, so the assertion sits
// on the session factory — the seam a fake transcriber cannot observe, and the one
// that silently received nothing while the suite stayed green.
@Suite("Orchestrator vocabulary bias")
struct OrchestratorVocabularyBiasTests {
    private static let vocabulary = [
        Term(term: "RCV", expansion: "RingCentral Video", lang: .en, weight: 2),
        Term(term: "GitHub", expansion: nil, lang: .en, weight: 1),
    ]

    private static func dependencies(
        transcriber: any Transcriber,
        cleaner: FakeCleaner,
        settings: DictationSettings
    ) -> Dependencies {
        Dependencies(
            transcriber: transcriber,
            cleaner: cleaner,
            injector: FakeInjector(outcome: .success),
            personalization: FakePersonalizationSource(terms: vocabulary),
            audio: FakeSystemAudioController(
                muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
            ),
            recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
            cueController: FakeDictationCueController(),
            log: RedactionSafeLog(subsystem: "slovo", category: "vocabulary-bias-test"),
            settings: FakeSettingsSource(settings).provider
        )
    }

    private static func makeOrchestrator(
        transcriber: any Transcriber,
        cleaner: FakeCleaner,
        usesVocabularyBias: Bool
    ) -> Orchestrator {
        var config = Config()
        config.usesVocabularyBias = usesVocabularyBias
        let settings = AppState(config: config, isOpenRouterKeyPresent: true).dictationSettings
        return PipelineFactory.makeOrchestrator(
            dependencies: dependencies(transcriber: transcriber, cleaner: cleaner, settings: settings)
        )
    }

    /// One dictation from key-down to injection.
    private static func runDictation(on orchestrator: Orchestrator) async {
        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()
    }

    /// Off (the default): the recognizer opens an unbiased session while cleanup
    /// still receives every term.
    /// Stated sensitivity: hand `begin` the vocabulary unconditionally (drop the
    /// `usesVocabularyBias` gate) → the recorded terms are ["RCV", "GitHub"] → RED;
    /// gate `sessionVocabulary` on the same flag → the cleaner's context empties → RED.
    @Test
    func offKeepsTheRecognizerUnbiasedButStillPersonalizesCleanup() async {
        let engine = FakeSpeechEngine(finalize: .success("raw words"))
        let cleaner = FakeCleaner(outcome: .success("CLEANED"))
        let orchestrator = Self.makeOrchestrator(
            transcriber: TranscriberFixtures.makeTranscriber(engine: engine),
            cleaner: cleaner,
            usesVocabularyBias: false
        )

        await Self.runDictation(on: orchestrator)

        #expect(engine.sessionBiasTerms.map { $0.map(\.term) } == [[]],
                "the switch is off, so no term may reach the speech engine")
        #expect(cleaner.calls.last?.context.vocabulary.map(\.term) == ["RCV", "GitHub"],
                "cleanup personalization is never gated by the recognizer switch")
    }

    /// On: the session vocabulary reaches the engine in weight order, unchanged.
    /// Stated sensitivity: keep passing `[]` (the pre-change wiring), or drop/reorder
    /// terms on the way to `begin` → the recorded terms differ → RED.
    @Test
    func onHandsTheSessionVocabularyToTheSpeechEngine() async {
        let engine = FakeSpeechEngine(finalize: .success("raw words"))
        let cleaner = FakeCleaner(outcome: .success("CLEANED"))
        let orchestrator = Self.makeOrchestrator(
            transcriber: TranscriberFixtures.makeTranscriber(engine: engine),
            cleaner: cleaner,
            usesVocabularyBias: true
        )

        await Self.runDictation(on: orchestrator)

        #expect(engine.sessionBiasTerms.map { $0.map(\.term) } == [["RCV", "GitHub"]],
                "the switch is on, so the session vocabulary must reach the speech engine")
        #expect(cleaner.calls.last?.context.vocabulary.map(\.term) == ["RCV", "GitHub"])
    }
}
