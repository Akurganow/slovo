import Foundation
import Testing

import SlovoCore

@Suite("Cleanup prompt builder")
struct PromptBuilderTests {
    private static func term(_ name: String, weight: Int, expansion: String? = nil) -> Term {
        Term(term: name, expansion: expansion, lang: .en, weight: weight)
    }

    private static func plainSystemText(style: WritingStyle = .casual, vocabulary: [Term] = []) -> String {
        PromptBuilder(maxVocabularyTerms: 3).buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: style, language: .auto),
            context: PersonalizationContext(vocabulary: vocabulary)
        ).systemBlocks.joined(separator: "\n")
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

    /// A kept term travels with the expansion the user recorded — the only production
    /// consumer of `Term.expansion` in the cleanup prompt; a term without a usable one
    /// stays bare rather than trailing empty parentheses. The header must announce the
    /// parenthetical as a recorded meaning, or the model reads it as text to emit.
    /// Stated sensitivity: revert the vocabulary mapping to `\.term` (expansions
    /// dropped), drop the empty-expansion guard (`PTT ()` rendered), or drop the
    /// "recorded meaning in parentheses" framing from the header → RED.
    @Test
    func vocabularyEntriesCarryTheRecordedExpansion() {
        let systemText = Self.plainSystemText(vocabulary: [
            Self.term("RCV", weight: 9, expansion: "RingCentral Video / RingCentral Meet"),
            Self.term("PTT", weight: 7, expansion: ""),
            Self.term("Slovo", weight: 5),
        ])

        #expect(systemText.contains(
            "Correct spellings of the speaker's terms, each with its recorded meaning in parentheses where known: "
                + "RCV (RingCentral Video / RingCentral Meet), PTT, Slovo"
        ))
    }

    /// Both halves of an entry are trimmed, and a row whose term is only whitespace is
    /// skipped outright rather than listing a blank entry. The blank row carries an
    /// expansion on purpose: without the skip it would render as " (Push To Talk)",
    /// which the empty-entry filter alone would not catch.
    /// Stated sensitivity: drop the term trim ("  RCV   (…)"), drop the expansion trim
    /// ("RCV (  RingCentral Video  )"), drop the blank-term skip ("…),  (Push To Talk),
    /// Slovo"), or drop the empty-entry filter ("…), , Slovo") → RED.
    @Test
    func vocabularyEntriesAreTrimmedAndBlankTermsSkipped() {
        let systemText = Self.plainSystemText(vocabulary: [
            Self.term("  RCV  ", weight: 9, expansion: "  RingCentral Video  "),
            Self.term("   ", weight: 7, expansion: "Push To Talk"),
            Self.term("Slovo", weight: 5),
        ])

        #expect(systemText.contains("in parentheses where known: RCV (RingCentral Video), Slovo"))
    }

    /// The block must drive CORRECTION, not only preservation: a transliterated
    /// mis-recognition ("RCV" heard as "РСВ") has to be replaced. The parenthetical
    /// guard keeps the recorded meaning out of the output, and the closing guard stops
    /// correction from inserting a term nobody said.
    /// Stated sensitivity: drop any one of the four instruction lines from
    /// `vocabularyBlock` → its expectation reddens.
    @Test
    func vocabularyBlockDemandsCorrectionWithoutInvention() {
        let systemText = Self.plainSystemText(vocabulary: [Self.term("RCV", weight: 9)])
        let correction = "If the transcript contains a phonetic or transliterated mis-recognition of one of these terms "
            + "— a Cyrillic rendering of a Latin acronym, a split-apart or wrongly cased form — "
            + "replace it with the spelling given here."

        #expect(systemText.contains("Preserve these terms verbatim wherever the transcript already spells them correctly."))
        #expect(systemText.contains(correction))
        #expect(systemText.contains(PromptBuilderFixtures.parentheticalGuardLine))
        #expect(systemText.contains("Never introduce a term from this list that the speaker did not say."))
    }

    /// The budget counts USABLE terms: a row that renders blank must not spend one of
    /// the top-N slots and push a real term out of the prompt. The blank row sits at
    /// weight 8, inside the head, with three valid rows around it.
    /// Stated sensitivity: filter the blank entries after `prefix` instead of before it
    /// (the previous behavior) → "Slovo" is pushed out of the list → RED.
    @Test
    func blankRowsDoNotConsumeATopNSlot() {
        let systemText = Self.plainSystemText(vocabulary: [
            Self.term("RCV", weight: 9, expansion: "RingCentral Video"),
            Self.term("  ", weight: 8),
            Self.term("PTT", weight: 7),
            Self.term("Slovo", weight: 5),
        ])

        #expect(systemText.contains("in parentheses where known: RCV (RingCentral Video), PTT, Slovo"))
    }

    /// A speaker with no vocabulary must never be told to correct toward an empty list,
    /// so every line of the block — not just its tag — has to be absent.
    /// Stated sensitivity: emit the vocabulary block unconditionally, or hoist any one
    /// of its five lines into a block every prompt receives → RED.
    @Test
    func noVocabularyBlockWhenVocabularyEmpty() {
        let systemText = Self.plainSystemText()

        #expect(!systemText.contains("<vocabulary>"))
        #expect(!systemText.contains("Correct spellings of the speaker's terms"))
        #expect(!systemText.contains("Preserve these terms verbatim wherever the transcript already spells them correctly."))
        #expect(!systemText.contains("replace it with the spelling given here"))
        #expect(!systemText.contains(PromptBuilderFixtures.parentheticalGuardLine))
        #expect(!systemText.contains("Never introduce a term from this list that the speaker did not say."))
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
        #expect(systemText.contains("do not ask for more context"))
        #expect(systemText.contains("If the transcript is a short test phrase"))
        #expect(systemText.contains("<output>1, 2, 3, проверяем, 1, 2, 3.</output>"))
        #expect(!systemText.contains("<output>\(raw)</output>"))
    }

    /// The plain task line must not read as a paraphrase license: it asks for the
    /// transcript back in the configured register, changed only where the rules allow.
    /// Stated sensitivity: revert the task line to "Rewrite the transcript into
    /// \(style)." → every expectation below reddens.
    @Test
    func plainTaskLineReturnsTheTranscriptInsteadOfRewritingIt() {
        let formal = Self.plainSystemText(style: .formal)
        let veryCasual = Self.plainSystemText(style: .veryCasual)

        #expect(formal.contains("Return the transcript as formal written prose, changing only what the rules below allow."))
        #expect(veryCasual.contains(
            "Return the transcript as very casual, conversational prose, changing only what the rules below allow."
        ))
        #expect(!formal.contains("Rewrite the transcript"))
        #expect(!veryCasual.contains("Rewrite the transcript"))
    }

    /// Stated sensitivity: removing the filler rule, the run-on guidance, the
    /// anti-compression example, or the translate-trap example makes the benchmark
    /// regress on the most common dictation cleanup.
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
        #expect(systemText.contains("Remove discourse fillers (such as"))
        #expect(systemText.contains("ну, вот, короче"))
        #expect(systemText.contains("split run-on text into clear sentences"))
        #expect(systemText.contains("<output>Переведи release notes на английский и запушь PR в GitHub.</output>"))
        // The anti-compression exemplar: a long complex sentence preserved whole.
        #expect(systemText.contains("что было решено, а что просто обсуждалось.</output>"))
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
        #expect(systemText.contains("Keyboard input language at dictation time: Russian (ru)."))
        #expect(systemText.contains("recieve → receive, relieve"))
        #expect(systemText.contains("teh → the"))
        #expect(systemText.contains("keep it unchanged"))
        // The advisory is supplementary context: it is the LAST system block,
        // wrapped in its provenance tag.
        #expect(prompt.systemBlocks.last?.hasPrefix("<advisory>\nAdvisory context (may be wrong") == true)
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

        #expect(systemText.contains("Keyboard input language at dictation time: English (en)."))
        #expect(!systemText.contains("flagged these tokens"))
    }

    /// Stated sensitivity: dropping the grammar rendering from the advisory block (so
    /// grammar findings are gathered but never reach the model) turns this red.
    @Test
    func advisoryBlockCarriesGrammarFindings() {
        let hints = CleanupHints(
            inputLocale: nil,
            spellFindings: [],
            grammarFindings: [
                GrammarFinding(
                    fragment: "is",
                    message: "The word ‘is’ may not agree with the rest of the sentence.",
                    corrections: ["am", "are"]
                ),
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
        #expect(systemText.contains("is: The word ‘is’ may not agree with the rest of the sentence."))
        #expect(systemText.contains("(suggested: am, are)"))
        // Grammar advice must stay as soft as the spelling advice: the checker
        // misfires on dictated speech and must never license a rewrite.
        #expect(systemText.contains("never let it reword a sentence the speaker clearly meant"))
    }

    /// Stated sensitivity: a grammar finding whose fragment could not be resolved must
    /// still advise via its message; prefixing an empty fragment would emit a stray
    /// ": " — this turns red.
    @Test
    func grammarFindingWithoutFragmentRendersMessageAlone() {
        let hints = CleanupHints(
            grammarFindings: [
                GrammarFinding(fragment: "", message: "Consider ‘an’ instead", corrections: ["an"]),
            ]
        )
        let prompt = PromptBuilder(maxVocabularyTerms: 3).buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual, language: .auto),
            context: PersonalizationContext(vocabulary: []),
            hints: hints
        )
        let systemText = prompt.systemBlocks.joined(separator: "\n\n")

        #expect(systemText.contains("flagged these fragments: Consider ‘an’ instead (suggested: an)"))
        #expect(!systemText.contains(": : "), "an unresolved fragment must not emit a stray separator")
    }

    /// Stated sensitivity: rendering the grammar sentences unconditionally makes this
    /// grammar-free case go red — the spelling half must survive alone, since Apple
    /// ships grammar rules for English only and most dictations have none.
    @Test
    func grammarSentencesAbsentWhenNoGrammarFindings() {
        let prompt = PromptBuilder(maxVocabularyTerms: 3).buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual, language: .auto),
            context: PersonalizationContext(vocabulary: []),
            hints: CleanupHints(spellFindings: [SpellFinding(token: "teh", guesses: ["the"])])
        )
        let systemText = prompt.systemBlocks.joined(separator: "\n\n")

        #expect(systemText.contains("teh → the"))
        #expect(!systemText.contains("grammar checker"))
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
