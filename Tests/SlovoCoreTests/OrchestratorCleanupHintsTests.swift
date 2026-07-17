import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

@Suite("Orchestrator cleanup hints")
struct OrchestratorCleanupHintsTests {
    private static var vocab: [Term] {
        [
            Term(term: "ExampleCorp", expansion: nil, lang: .en, weight: 9),
            Term(term: "GitHub", expansion: nil, lang: .en, weight: 7),
        ]
    }

    private static func deps(
        cleaner: FakeCleaner,
        inputSource: (any InputSourceLanguageReading)?,
        spell: (any SpellCheckHintProviding)?
    ) -> Dependencies {
        Dependencies(
            transcriber: FakeTranscriber(outcome: .success("hi")),
            cleaner: cleaner,
            injector: FakeInjector(outcome: .success),
            personalization: FakePersonalizationSource(terms: vocab),
            audio: FakeSystemAudioController(
                muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
            ),
            recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
            log: RedactionSafeLog(subsystem: "slovo", category: "orch-hints-test"),
            inputSourceLanguage: inputSource,
            spellCheckHints: spell
        )
    }

    private static func runSession(_ orchestrator: Orchestrator) async {
        await orchestrator.handle(.startRequested)
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()
    }

    /// Stated sensitivity: an orchestrator that never gathers/forwards hints passes
    /// empty hints to the cleaner — the recorded locale and findings are empty →
    /// RED.
    @Test
    func gatheredHintsReachTheCleaner() async {
        let cleaner = FakeCleaner(outcome: .success("HI"))
        let findings = [SpellFinding(token: "teh", guesses: ["the"])]
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(
                cleaner: cleaner,
                inputSource: FakeInputSourceLanguageReader(language: "ru"),
                spell: FakeSpellCheckHintProvider(findings: findings)
            )
        )

        await Self.runSession(orchestrator)

        #expect(cleaner.calls.last?.hints.inputLocale == "ru")
        #expect(cleaner.calls.last?.hints.spellFindings == findings)
    }

    /// Stated sensitivity: the spell pass must use the session vocabulary as its
    /// ignore list; passing `[]` instead makes the recorded ignore list miss the
    /// terms → RED.
    @Test
    func spellPassIgnoresSessionVocabulary() async {
        let cleaner = FakeCleaner(outcome: .success("HI"))
        let provider = FakeSpellCheckHintProvider(findings: [])
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(),
            dependencies: Self.deps(
                cleaner: cleaner,
                inputSource: nil,
                spell: provider
            )
        )

        await Self.runSession(orchestrator)

        let ignored = provider.calls.last?.ignoredVocabulary ?? []
        #expect(ignored.contains("ExampleCorp") && ignored.contains("GitHub"),
                "the spell pass must ignore the user's vocabulary; got \(ignored)")
    }

    /// Stated sensitivity: an orchestrator that ignores `useSpellCheckHints` runs
    /// the spell pass even when off — the provider is called and findings survive →
    /// RED. The locale hint has no toggle, so it must still appear.
    @Test
    func spellPassSkippedWhenToggleOffButLocaleRemains() async {
        let cleaner = FakeCleaner(outcome: .success("HI"))
        let provider = FakeSpellCheckHintProvider(findings: [SpellFinding(token: "teh", guesses: ["the"])])
        let orchestrator = PipelineFactory.makeOrchestrator(
            config: Config(useSpellCheckHints: false),
            dependencies: Self.deps(
                cleaner: cleaner,
                inputSource: FakeInputSourceLanguageReader(language: "en"),
                spell: provider
            )
        )

        await Self.runSession(orchestrator)

        #expect(provider.calls.isEmpty, "the spell provider must not be consulted when the toggle is off")
        #expect(cleaner.calls.last?.hints.spellFindings.isEmpty == true)
        #expect(cleaner.calls.last?.hints.inputLocale == "en", "the locale hint has no toggle and must remain")
    }
}
