import Foundation
import Testing

import SlovoCore

// Epic 06 — AC-4: `PromptBuilder` puts `cache_control` on the LAST system block
// (never the user block) and keeps the top-N vocabulary terms BY WEIGHT in
// descending order.
//
// Contract under test (implementer builds `Sources/SlovoCore/Cleaner/PromptBuilder.swift`
// + `AnthropicRequest.swift` per plan §5/§6; CURRENTLY the WRONG-ON-PURPOSE
// `_RedScaffold_Cleaner.swift` stub puts cache_control on the USER block and
// keeps the first-N terms unsorted → RED).
//
// FIXTURE ANCHOR RULE (P1): vocabulary terms are neutral placeholders (term-9,
// term-7, ...) and must not contain private vocabulary.
@Suite("Epic 06 AC-4 PromptBuilder")
struct PromptBuilderTests {
    private static func term(_ name: String, weight: Int) -> Term {
        Term(term: name, expansion: nil, lang: .en, weight: weight)
    }

    /// cache_control on the LAST system block, NOT the user block.
    /// Stated sensitivity: move cache_control to the user block → user-block
    /// assertion fails → RED. (The scaffold puts it on the user block → RED.)
    @Test
    func cacheControlOnLastSystemBlockNotUserBlock() {
        let context = PersonalizationContext(vocabulary: [Self.term("a", weight: 1)])
        let request = PromptBuilder(maxVocabularyTerms: 3)
            .build(raw: "hello", config: CleanupConfig(writingStyle: .formal, language: .auto), context: context)

        #expect(request.system.last?.cacheControl != nil,
                "the LAST system block must carry cache_control")
        #expect(request.messages.allSatisfy { $0.cacheControl == nil },
                "the user/message block must NEVER carry cache_control (it varies every call)")
    }

    /// Over-budget vocabulary (weights [5,3,9,1,7], max 3) keeps the top-3 by
    /// weight [9,7,5] IN THAT ORDER.
    /// Stated sensitivity: drop/reverse the weight sort → kept set ≠ [9,7,5] or
    /// order wrong → RED. The expected [9,7,5] is computed from the FIXTURE
    /// weights, NOT by re-running the builder (no tautology). (The scaffold keeps
    /// the first 3 unsorted → ["w5","w3","w9"] → RED.)
    @Test
    func keepsTopNVocabularyByWeightInOrder() {
        let vocab = [
            Self.term("w5", weight: 5),
            Self.term("w3", weight: 3),
            Self.term("w9", weight: 9),
            Self.term("w1", weight: 1),
            Self.term("w7", weight: 7),
        ]
        let request = PromptBuilder(maxVocabularyTerms: 3)
            .build(raw: "hello", config: CleanupConfig(writingStyle: .formal, language: .auto),
                   context: PersonalizationContext(vocabulary: vocab))

        // The system blocks embed the kept terms; the top-3 by weight are w9,w7,w5.
        let systemText = request.system.map(\.text).joined(separator: "\n")
        let keptInOrder = ["w9", "w7", "w5"]
        // Each kept term present, in descending-weight order, and the dropped ones absent.
        let positions = keptInOrder.map { systemText.range(of: $0)?.lowerBound }
        #expect(positions.allSatisfy { $0 != nil }, "all top-3-by-weight terms must be present: \(systemText)")
        if let p9 = positions[0], let p7 = positions[1], let p5 = positions[2] {
            #expect(p9 < p7 && p7 < p5, "kept terms must be in descending-weight order [w9,w7,w5]")
        }
        #expect(!systemText.contains("w3") && !systemText.contains("w1"),
                "the below-budget terms (w3,w1) must be dropped")
    }

    /// The model id is a cleanup config decision, not a hidden literal inside the
    /// request builder.
    /// Stated sensitivity: hard-code `claude-haiku-4-5` in the builder while config
    /// asks for `claude-test-model` -> RED.
    @Test
    func requestModelComesFromCleanupConfig() {
        let request = PromptBuilder(maxVocabularyTerms: 3)
            .build(
                raw: "hello",
                config: CleanupConfig(model: "claude-test-model", writingStyle: .formal, language: .auto),
                context: PersonalizationContext(vocabulary: [])
            )

        #expect(request.model == "claude-test-model",
                "the Anthropic model must come from configuration, got \(request.model)")
    }

    /// Short dictation snippets are still transcripts to clean, not chat prompts.
    /// Stated sensitivity: remove the assistant-style guardrails from the system
    /// prompt or make the example byte-identical -> the required instruction
    /// fragments disappear or the example assertion fails -> RED.
    @Test
    func promptRequiresTransformOnlyReplyForShortDictation() {
        let raw = "1 2 3 проверяем 1 2 3"
        let request = PromptBuilder(maxVocabularyTerms: 3)
            .build(
                raw: raw,
                config: CleanupConfig(writingStyle: .casual, language: .auto),
                context: PersonalizationContext(vocabulary: [])
            )
        let systemText = request.system.map(\.text).joined(separator: "\n")

        #expect(request.messages.first?.content == raw,
                "the model input must carry the exact raw transcript to be transformed")
        #expect(systemText.contains("Return only the cleaned transcript"),
                "the model must be constrained to output only the transcript")
        #expect(systemText.contains("Do not ask for context"),
                "the model must not answer short dictation as an interactive chat")
        #expect(systemText.contains("If the transcript is a short test phrase"),
                "short test utterances must be treated as valid dictation")
        #expect(systemText.contains("<output>1, 2, 3, проверяем, 1, 2, 3.</output>"),
                "the short-test example must demonstrate cleanup, not byte-identical pass-through")
        #expect(!systemText.contains("<output>\(raw)</output>"),
                "the prompt must not teach byte-identical output for this case")
    }

    /// Stated sensitivity: weakening the language boundary lets a cleaner turn
    /// Russian dictation into English prose instead of preserving source language.
    @Test
    func promptExplicitlyForbidsTranslation() {
        let request = PromptBuilder(maxVocabularyTerms: 3)
            .build(
                raw: "прибери мусор",
                config: CleanupConfig(writingStyle: .casual, language: .ru),
                context: PersonalizationContext(vocabulary: [])
            )
        let systemText = request.system.map(\.text).joined(separator: "\n")

        #expect(systemText.contains("Never translate"))
        #expect(systemText.contains("Output language must match the transcript language"))
        #expect(systemText.contains("<transcript>прибери мусор</transcript>"))
        #expect(systemText.contains("<output>Прибери мусор.</output>"))
        #expect(systemText.contains("<transcript>запусти swift test и открой pull request</transcript>"))
        #expect(systemText.contains("<output>Запусти swift test и открой pull request.</output>"))
        #expect(!systemText.contains("<output>Clean up the trash.</output>"))
        #expect(!systemText.contains("<output>Run swift test and open a pull request.</output>"))
    }
}
