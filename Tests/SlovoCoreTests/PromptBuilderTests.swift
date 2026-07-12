import Foundation
import Testing

import SlovoCore

@Suite("Cleanup prompt builder")
struct PromptBuilderTests {
    private static func term(_ name: String, weight: Int) -> Term {
        Term(term: name, expansion: nil, lang: .en, weight: weight)
    }

    /// Stated sensitivity: dropping or reversing the weight sort changes the
    /// exact high-value vocabulary order sent to OpenRouter.
    @Test
    func keepsTopNVocabularyByWeightInOrder() {
        let vocabulary = [
            Self.term("w5", weight: 5),
            Self.term("w3", weight: 3),
            Self.term("w9", weight: 9),
            Self.term("w1", weight: 1),
            Self.term("w7", weight: 7),
        ]
        let prompt = PromptBuilder(maxVocabularyTerms: 3).buildPrompt(
            raw: "hello",
            config: CleanupConfig(model: "openai/gpt-5.6-luna", writingStyle: .formal, language: .auto),
            context: PersonalizationContext(vocabulary: vocabulary)
        )
        let systemText = prompt.systemBlocks.joined(separator: "\n")

        let positions = ["w9", "w7", "w5"].map { systemText.range(of: $0)?.lowerBound }
        #expect(positions.allSatisfy { $0 != nil }, "all top-3-by-weight terms must be present: \(systemText)")
        if let p9 = positions[0], let p7 = positions[1], let p5 = positions[2] {
            #expect(p9 < p7 && p7 < p5, "kept terms must be in descending-weight order")
        }
        #expect(!systemText.contains("w3") && !systemText.contains("w1"))
    }

    /// Stated sensitivity: hard-coding a provider model in the prompt builder
    /// makes custom OpenRouter model selection ineffective.
    @Test
    func promptModelComesFromCleanupConfig() {
        let prompt = PromptBuilder(maxVocabularyTerms: 3).buildPrompt(
            raw: "hello",
            config: CleanupConfig(model: "custom/provider-model", writingStyle: .formal, language: .auto),
            context: PersonalizationContext(vocabulary: [])
        )

        #expect(prompt.model == "custom/provider-model")
    }

    /// Stated sensitivity: weakening the transform-only guardrails lets short
    /// dictation snippets be answered as chat instead of cleaned as transcripts.
    @Test
    func promptRequiresTransformOnlyReplyForShortDictation() {
        let raw = "1 2 3 проверяем 1 2 3"
        let prompt = PromptBuilder(maxVocabularyTerms: 3).buildPrompt(
            raw: raw,
            config: CleanupConfig(writingStyle: .casual, language: .auto),
            context: PersonalizationContext(vocabulary: [])
        )
        let systemText = prompt.systemBlocks.joined(separator: "\n")

        #expect(prompt.input == raw)
        #expect(systemText.contains("Return only the cleaned transcript"))
        #expect(systemText.contains("Do not ask for context"))
        #expect(systemText.contains("If the transcript is a short test phrase"))
        #expect(systemText.contains("<output>1, 2, 3, проверяем, 1, 2, 3.</output>"))
        #expect(!systemText.contains("<output>\(raw)</output>"))
    }

    /// Stated sensitivity: removing Russian filler examples or run-on splitting
    /// guidance makes the benchmark regress on the most common dictation cleanup.
    @Test
    func promptTeachesRussianFillerRemovalAndRunOnSplitting() {
        let prompt = PromptBuilder(maxVocabularyTerms: 3).buildPrompt(
            raw: "короче я сейчас попробую поговорить подольше ну чтобы проверить как работает cleanup",
            config: CleanupConfig(writingStyle: .casual, language: .auto),
            context: PersonalizationContext(vocabulary: [])
        )
        let systemText = prompt.systemBlocks.joined(separator: "\n")

        #expect(systemText.contains("Never translate"))
        #expect(systemText.contains("Output language must match the transcript language"))
        #expect(systemText.contains("Remove discourse fillers such as"))
        #expect(systemText.contains("ну, вот, короче"))
        #expect(systemText.contains("Split run-on dictated text into clear sentences"))
        #expect(systemText.contains("<output>Запушь PR в GitHub, пожалуйста.</output>"))
        #expect(systemText.contains("<output>Сейчас попробую поговорить подольше. Проверю, как работает cleanup.</output>"))
    }

    /// Stated sensitivity: dropping the advisory append (so hints never reach the
    /// prompt) makes the present-case assertions go red.
    @Test
    func advisoryBlockCarriesLocaleAndSpellFindings() {
        let hints = CleanupHints(
            inputLocale: "ru",
            spellFindings: [
                SpellFinding(token: "recieve", guesses: ["receive", "relieve"]),
                SpellFinding(token: "teh", guesses: ["the"]),
            ]
        )
        let prompt = PromptBuilder(maxVocabularyTerms: 3).buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual, language: .auto),
            context: PersonalizationContext(vocabulary: []),
            hints: hints
        )
        let systemText = prompt.systemBlocks.joined(separator: "\n\n")

        #expect(systemText.contains("Advisory context (may be wrong"))
        #expect(systemText.contains("Keyboard input language at dictation time: ru."))
        #expect(systemText.contains("recieve → receive, relieve"))
        #expect(systemText.contains("teh → the"))
        #expect(systemText.contains("keep it unchanged"))
        // The advisory is supplementary context: it is the LAST system block.
        #expect(prompt.systemBlocks.last?.hasPrefix("Advisory context (may be wrong") == true)
    }

    /// Stated sensitivity: appending the advisory block unconditionally makes this
    /// no-hints (toggle off AND no locale) case go red.
    @Test
    func noAdvisoryBlockWhenHintsEmpty() {
        let prompt = PromptBuilder(maxVocabularyTerms: 3).buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual, language: .auto),
            context: PersonalizationContext(vocabulary: []),
            hints: CleanupHints()
        )
        let systemText = prompt.systemBlocks.joined(separator: "\n\n")

        #expect(!systemText.contains("Advisory context"))
    }

    /// Stated sensitivity: appending the spell sentences unconditionally makes this
    /// locale-only (spell toggle off, findings empty) case go red — the locale line
    /// must survive while the spell sentences must not appear.
    @Test
    func localeLineRemainsButSpellSentencesAbsentWhenNoFindings() {
        let prompt = PromptBuilder(maxVocabularyTerms: 3).buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual, language: .auto),
            context: PersonalizationContext(vocabulary: []),
            hints: CleanupHints(inputLocale: "en", spellFindings: [])
        )
        let systemText = prompt.systemBlocks.joined(separator: "\n\n")

        #expect(systemText.contains("Keyboard input language at dictation time: en."))
        #expect(!systemText.contains("flagged these tokens"))
    }

    /// Stated sensitivity: the existing 3-arg overload must keep producing NO
    /// advisory block, so old callers are unchanged; adding a block there turns red.
    @Test
    func threeArgOverloadEmitsNoAdvisoryBlock() {
        let prompt = PromptBuilder(maxVocabularyTerms: 3).buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual, language: .auto),
            context: PersonalizationContext(vocabulary: [])
        )

        #expect(!prompt.systemBlocks.joined(separator: "\n\n").contains("Advisory context"))
    }
}
