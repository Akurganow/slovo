import Foundation
import Testing

import SlovoCore

@Suite("Cleanup prompt builder")
struct PromptBuilderTests {
    private static func term(_ name: String, weight: Int, expansion: String? = nil) -> Term {
        Term(term: name, expansion: expansion, lang: .en, weight: weight)
    }

    private static func plainSystemText(style: WritingStyle = .casual, vocabulary: [Term] = []) -> String {
        PromptBuilder().buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: style),
            context: PersonalizationContext(vocabulary: vocabulary)
        ).systemText
    }

    /// Terms are listed weight-descending, whatever order the context arrives in — the
    /// model reads the head as the most important spellings.
    /// Stated sensitivity: drop or reverse the weight sort → the rendered list stops
    /// being `w9, w7, w5, w3, w1` → RED.
    @Test
    func rendersVocabularyByWeightDescending() {
        let systemText = Self.plainSystemText(vocabulary: [
            Self.term("w5", weight: 5),
            Self.term("w3", weight: 3),
            Self.term("w9", weight: 9),
            Self.term("w1", weight: 1),
            Self.term("w7", weight: 7),
        ])

        #expect(systemText.contains("in parentheses where known: w9, w7, w5, w3, w1"))
    }

    /// The cleanup prompt carries the WHOLE vocabulary — there is no term budget to
    /// spend, only the ~1k tokens of system prefix it costs. 60 terms is more than the
    /// retired 50-term cap and more than any plausible round-number cap, so a silently
    /// reintroduced one cannot hide here. Names are zero-padded so that no term is a
    /// substring of another: unpadded, "term-6" would be found inside "term-60" and a
    /// cap keeping only the head could pass.
    /// Stated sensitivity: reintroduce `.prefix(50)` → exactly 10 terms stop rendering
    /// (term-051…term-060) → RED; `.prefix(25)` drops 35, `.prefix(10)` drops 50 → RED.
    /// Weight 1 throughout is deliberate: the order is then purely term-driven, so the
    /// padded names make the surviving set an exact, readable prefix.
    @Test
    func rendersEveryTermWithNoCap() {
        let names = (1...60).map { String(format: "term-%03d", $0) }
        let vocabulary = names.map { Self.term($0, weight: 1) }

        let systemText = Self.plainSystemText(vocabulary: vocabulary)

        let missing = names.filter { !systemText.contains($0) }
        #expect(missing.isEmpty, "all 60 terms must render; missing \(missing.count): \(missing)")
    }

    /// Equal weights must not leave the rendered order to `sorted`'s unspecified tie
    /// behavior: the block is a cache prefix, so a reshuffle between dictations costs
    /// a cache miss wherever prefix caching applies. This pins THIS side's own
    /// ordering — the store's SQL ORDER BY is a separate decision under a separate
    /// collation, and the two are deliberately not compared. `Bravo` makes the tie
    /// case-sensitive: `Bravo`/`bravo` differ only in one byte, the case an
    /// equality-reporting comparator would leave free to swap.
    /// Stated sensitivity: drop the scalar tie-break (leaving `$0.weight > $1.weight`)
    /// → Swift's sort leaves the tie group in arrival order and the list renders
    /// `zulu, delta, charlie, bravo, alpha, Bravo` → RED.
    @Test
    func equalWeightTermsRenderInTermOrder() {
        let systemText = Self.plainSystemText(vocabulary: [
            Self.term("delta", weight: 4),
            Self.term("charlie", weight: 4),
            Self.term("zulu", weight: 9),
            Self.term("bravo", weight: 4),
            Self.term("alpha", weight: 4),
            Self.term("Bravo", weight: 4),
        ])

        #expect(systemText.contains("in parentheses where known: zulu, Bravo, alpha, bravo, charlie, delta"))
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

    /// A speaker with no vocabulary must never be told to correct toward an empty list,
    /// so every line of the block — not just its tag — has to be absent.
    /// Stated sensitivity: emit the vocabulary block unconditionally, or hoist any one
    /// of its six lines into a block every prompt receives → RED.
    @Test
    func noVocabularyBlockWhenVocabularyEmpty() {
        let systemText = Self.plainSystemText()

        #expect(!systemText.contains("<vocabulary>"))
        #expect(!systemText.contains("Correct spellings of the speaker's terms"))
        #expect(!systemText.contains("Preserve these terms verbatim wherever the transcript already spells them correctly."))
        #expect(!systemText.contains("replace it with the spelling given here"))
        #expect(!systemText.contains("An ordinary word in its everyday sense"))
        #expect(!systemText.contains(PromptBuilderFixtures.parentheticalGuardLine))
        #expect(!systemText.contains("Never introduce a term from this list that the speaker did not say."))
    }

    /// Stated sensitivity: hard-coding a provider model in the prompt builder
    /// makes custom OpenRouter model selection ineffective.
    @Test
    func promptModelComesFromCleanupConfig() {
        let prompt = PromptBuilder().buildPrompt(
            raw: "hello",
            config: CleanupConfig(model: "custom/provider-model", writingStyle: .formal),
            context: PersonalizationContext(vocabulary: [])
        )

        #expect(prompt.model == "custom/provider-model")
    }

    /// Stated sensitivity: send the input without its `<transcript>` wrapper, or
    /// drop the short-dictation example or let its output echo the raw input → RED.
    @Test
    func shortDictationInputIsWrappedAndTaughtByAnExample() {
        let raw = "1 2 3 проверяем 1 2 3"
        let prompt = PromptBuilder().buildPrompt(
            raw: raw,
            config: CleanupConfig(writingStyle: .casual),
            context: PersonalizationContext(vocabulary: [])
        )
        let systemText = prompt.systemText

        #expect(prompt.input == "<transcript>\(raw)</transcript>",
                "real input must match the few-shot <transcript> format byte-for-byte")
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

    /// The formal and very casual style lines name the word changes the rules below would forbid and allow
    /// only those. The
    /// translate prompt carries no style line: its register is the "as \(style)" phrase.
    /// Stated sensitivity: return "" for the formal style line → the first expectation
    /// reddens; render the style line in translate mode → the translate expectations redden → RED.
    @Test
    func styleLinesExtendTheFixesInPlainModeOnly() {
        #expect(Self.plainSystemText(style: .formal).contains("Formal style: the rules below forbid new or changed words, except these changes"))
        #expect(Self.plainSystemText(style: .veryCasual).contains("Very casual style: the rules below forbid changed words, except this change"))

        for style in [WritingStyle.formal, .casual, .veryCasual] {
            let translate = PromptBuilder().buildPrompt(
                raw: "hello",
                config: CleanupConfig(writingStyle: style, translationTargetLanguage: .ru, translate: true),
                context: PersonalizationContext(vocabulary: [])
            ).systemText
            #expect(!translate.contains("Formal style"))
            #expect(!translate.contains("Casual style"))
            #expect(!translate.contains("Very casual style"))
        }
    }

    /// The filler and run-on rules are pinned by the plain golden; this pins the two
    /// examples that teach them on Russian input.
    /// Stated sensitivity: removing the translate-trap example or the
    /// anti-compression example → RED.
    @Test
    func promptCarriesTranslateTrapAndAntiCompressionExamples() {
        let prompt = PromptBuilder().buildPrompt(
            raw: "короче я сейчас попробую поговорить подольше ну чтобы проверить как работает cleanup",
            config: CleanupConfig(writingStyle: .casual),
            context: PersonalizationContext(vocabulary: [])
        )
        let systemText = prompt.systemText

        #expect(systemText.contains("<output>Переведи release notes на английский и запушь PR в GitHub.</output>"))
        // The anti-compression exemplar: a long complex sentence preserved whole.
        #expect(systemText.contains("что было решено, а что просто обсуждалось.</output>"))
    }

    /// Stated sensitivity: dropping the advisory append (so hints never reach the
    /// prompt) makes the present-case assertions go red. Restoring the spell sentence
    /// without its last clause ("use a suggestion only to fix a misspelled common word")
    /// makes the clause expectation go red.
    @Test
    func advisoryBlockCarriesLocaleAndSpellFindings() {
        let hints = CleanupHints(
            inputLocale: "ru",
            spellFindings: [
                SpellFinding(token: "recieve", guesses: ["receive", "relieve"]),
                SpellFinding(token: "teh", guesses: ["the"]),
            ]
        )
        let prompt = PromptBuilder().buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual),
            context: PersonalizationContext(vocabulary: []),
            hints: hints
        )
        let systemText = prompt.systemText

        #expect(systemText.contains("Advisory context (may be wrong"))
        #expect(systemText.contains("Keyboard input language at dictation time: Russian (ru)."))
        #expect(systemText.contains("recieve → receive, relieve"))
        #expect(systemText.contains("teh → the"))
        #expect(systemText.contains("keep it unchanged"))
        #expect(systemText.contains("use a suggestion only to fix a misspelled common word"))
        // The advisory is supplementary context, wrapped in its provenance tag.
        #expect(prompt.advisory?.hasPrefix("<advisory>\nAdvisory context (may be wrong") == true)
    }

    /// Stated sensitivity: appending the advisory block unconditionally makes this
    /// no-hints (toggle off AND no locale) case go red.
    @Test
    func noAdvisoryBlockWhenHintsEmpty() {
        let prompt = PromptBuilder().buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual),
            context: PersonalizationContext(vocabulary: []),
            hints: CleanupHints()
        )
        let systemText = prompt.systemText

        #expect(!systemText.contains("Advisory context"))
    }

    /// Stated sensitivity: appending the spell sentences unconditionally makes this
    /// locale-only (spell toggle off, findings empty) case go red — the locale line
    /// must survive while the spell sentences must not appear.
    @Test
    func localeLineRemainsButSpellSentencesAbsentWhenNoFindings() {
        let prompt = PromptBuilder().buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual),
            context: PersonalizationContext(vocabulary: []),
            hints: CleanupHints(inputLocale: "en", spellFindings: [])
        )
        let systemText = prompt.systemText

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
        let prompt = PromptBuilder().buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual),
            context: PersonalizationContext(vocabulary: []),
            hints: hints
        )
        let systemText = prompt.systemText

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
        let prompt = PromptBuilder().buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual),
            context: PersonalizationContext(vocabulary: []),
            hints: hints
        )
        let systemText = prompt.systemText

        #expect(systemText.contains("flagged these fragments: Consider ‘an’ instead (suggested: an)"))
        #expect(!systemText.contains(": : "), "an unresolved fragment must not emit a stray separator")
    }

    /// Stated sensitivity: rendering the grammar sentences unconditionally makes this
    /// grammar-free case go red — the spelling half must survive alone, since Apple
    /// ships grammar rules for English only and most dictations have none.
    @Test
    func grammarSentencesAbsentWhenNoGrammarFindings() {
        let prompt = PromptBuilder().buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual),
            context: PersonalizationContext(vocabulary: []),
            hints: CleanupHints(spellFindings: [SpellFinding(token: "teh", guesses: ["the"])])
        )
        let systemText = prompt.systemText

        #expect(systemText.contains("teh → the"))
        #expect(!systemText.contains("grammar checker"))
    }

    private static let advisoryHeader = "Advisory context (may be wrong — use only if it helps, never force; "
        + "it informs the cleanup and asks nothing, so the output is still only the cleaned text):"

    private static func collisionLine(word: String, term: String) -> String {
        "The transcript's word \"\(word)\" shares its letters with the listed term \(term); "
            + "keep it as transcribed unless the sentence uses it as the name \(term)."
    }

    private static func prompt(raw: String, terms: [String], hints: CleanupHints = CleanupHints()) -> CleanupPrompt {
        PromptBuilder().buildPrompt(
            raw: raw,
            config: CleanupConfig(writingStyle: .casual),
            context: PersonalizationContext(vocabulary: terms.enumerated().map { index, term in
                Term(term: term, expansion: nil, lang: .en, weight: 100 - index)
            }),
            hints: hints
        )
    }

    /// Stated sensitivity: drop the collision lines, emit them for a word the term
    /// does not match, list them in vocabulary order instead of transcript order, or
    /// leave the header off an advisory that has no hints → RED.
    @Test
    func everydayWordsThatOnlyShareLettersWithTermsGetOneLineEachInTranscriptOrder() {
        let prompt = Self.prompt(
            raw: "We booked two rooms. A cop stopped us, and the ads were everywhere.",
            terms: ["ADS", "COP", "GitHub", "Rooms"]
        )

        #expect(prompt.advisory == [
            "<advisory>",
            Self.advisoryHeader,
            Self.collisionLine(word: "rooms", term: "Rooms"),
            Self.collisionLine(word: "cop", term: "COP"),
            Self.collisionLine(word: "ads", term: "ADS"),
            "</advisory>",
        ].joined(separator: "\n"))
    }

    /// Stated sensitivity: report a term the transcript also holds as listed, repeat
    /// the line for a term listed twice, or order a term by a later occurrence than its
    /// first → RED.
    @Test
    func aTermWrittenAsListedGivesNoLineAndATermListedTwiceGivesOne() {
        let exact = Self.prompt(raw: "COP and cop again", terms: ["COP"])
        #expect(!exact.systemText.contains("<advisory>"))

        let repeated = Self.prompt(raw: "cop and cop again", terms: ["COP", "COP"])
        #expect(repeated.advisory == [
            "<advisory>",
            Self.advisoryHeader,
            Self.collisionLine(word: "cop", term: "COP"),
            "</advisory>",
        ].joined(separator: "\n"))

        let reordered = Self.prompt(raw: "cop, then ads, then cop again", terms: ["COP", "ADS"])
        #expect(reordered.advisory == [
            "<advisory>",
            Self.advisoryHeader,
            Self.collisionLine(word: "cop", term: "COP"),
            Self.collisionLine(word: "ads", term: "ADS"),
            "</advisory>",
        ].joined(separator: "\n"))
    }

    /// Stated sensitivity: emit the advisory whenever the vocabulary is non-empty
    /// instead of only when a word collides → RED.
    @Test
    func noCollisionAndNoHintsGivesNoAdvisoryBlock() {
        let prompt = Self.prompt(raw: "We booked a table at COP.", terms: ["ADS", "COP"])

        #expect(prompt.prefixBlocks.count == 2)
        #expect(prompt.advisory == nil)
        #expect(!prompt.systemText.contains("<advisory>"))
    }

    /// Stated sensitivity: ignore the term's own spacing or punctuation, or skip
    /// multi-word terms → RED.
    @Test
    func multiWordAndPunctuatedTermsCollideOnlyAtWordBoundariesInAnotherCase() {
        let prompt = Self.prompt(raw: "we use open  ai and Node.JS", terms: ["Open AI", "node.js"])

        #expect(prompt.advisory == [
            "<advisory>",
            Self.advisoryHeader,
            Self.collisionLine(word: "open ai", term: "Open AI"),
            Self.collisionLine(word: "node.js", term: "node.js"),
            "</advisory>",
        ].joined(separator: "\n"))

        let exact = Self.prompt(raw: "we use Open AI and node.js", terms: ["Open AI", "node.js"])
        #expect(!exact.systemText.contains("<advisory>"))
    }

    /// Stated sensitivity: put the collision lines before the hint lines, or drop them
    /// when hints exist → RED.
    @Test
    func collisionLinesFollowTheHintLines() {
        let prompt = Self.prompt(raw: "the ads", terms: ["ADS"], hints: CleanupHints(inputLocale: "ru"))
        let lines = (prompt.advisory ?? "").split(separator: "\n").map(String.init)

        #expect(lines.first == "<advisory>")
        #expect(lines.dropFirst().first == Self.advisoryHeader)
        #expect(lines.contains("Keyboard input language at dictation time: Russian (ru)."))
        #expect(lines.dropLast().last == Self.collisionLine(word: "ads", term: "ADS"))
        #expect(lines.last == "</advisory>")
    }

    /// Stated sensitivity: the existing 3-arg overload must keep producing NO
    /// advisory block, so old callers are unchanged; adding a block there turns red.
    @Test
    func threeArgOverloadEmitsNoAdvisoryBlock() {
        let prompt = PromptBuilder().buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual),
            context: PersonalizationContext(vocabulary: [])
        )

        #expect(!prompt.systemText.contains("Advisory context"))
    }

    /// The system message is the prefix blocks, then the advisory, each pair joined by one
    /// blank line. Providers send exactly this text, and the benchmark hashes it.
    /// Stated sensitivity: join with a single newline, or put the advisory first → RED.
    @Test(arguments: [("C", "A\n\nB\n\nC"), (String?.none, "A\n\nB")])
    func systemTextJoinsThePrefixThenTheAdvisoryByABlankLine(advisory: String?, expected: String) {
        let prompt = CleanupPrompt(model: "m", prefixBlocks: ["A", "B"], advisory: advisory, input: "x")

        #expect(prompt.systemText == expected)
    }

    /// The advisory names the standard language, not the catalogue's synonym ("Moldovan" for ro),
    /// and a translate target names its script where a language has two.
    /// Stated sensitivity: resolve the advisory language through the catalogue's displayName →
    /// "Moldovan (ro)" and the Romanian expectation reddens; drop the "Cyrillic" qualifier → RED;
    /// drop "ht", "lb" or "pa" from the standard names, drop "pa" from the script names, or look up
    /// the standard names before the script names → RED.
    @Test
    func standardLanguageNamesReachTheAdvisoryAndTheTranslateTarget() {
        let advisory = PromptBuilder().buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual),
            context: PersonalizationContext(vocabulary: []),
            hints: CleanupHints(inputLocale: "ro")
        ).systemText
        #expect(advisory.contains("Keyboard input language at dictation time: Romanian (ro)."))
        #expect(!advisory.contains("Moldovan"))

        let serbian = PromptBuilder().buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual, translationTargetLanguage: Language(rawValue: "sr"), translate: true),
            context: PersonalizationContext(vocabulary: [])
        ).systemText
        #expect(serbian.contains("Translate the transcript into Serbian, in Cyrillic script and remove dictation artifacts"))

        for (code, name) in [("ht", "Haitian Creole"), ("lb", "Luxembourgish"), ("pa", "Punjabi")] {
            let advisory = PromptBuilder().buildPrompt(
                raw: "hello",
                config: CleanupConfig(writingStyle: .casual),
                context: PersonalizationContext(vocabulary: []),
                hints: CleanupHints(inputLocale: code)
            ).systemText
            #expect(advisory.contains("Keyboard input language at dictation time: \(name) (\(code))."))
        }
        let punjabi = PromptBuilder().buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual, translationTargetLanguage: Language(rawValue: "pa"), translate: true),
            context: PersonalizationContext(vocabulary: [])
        ).systemText
        #expect(punjabi.contains("Translate the transcript into Punjabi, in Gurmukhi script and remove dictation artifacts"))
    }

    /// The advisory's header ends with the output of its mode: the cleaned text in plain mode,
    /// the translated text in translate mode.
    /// Stated sensitivity: name "cleaned" in every mode → the translate expectation reddens → RED.
    @Test
    func advisoryHeaderNamesTheOutputOfItsMode() {
        let hints = CleanupHints(inputLocale: "ro")
        let plain = PromptBuilder().buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual),
            context: PersonalizationContext(vocabulary: []),
            hints: hints
        )
        let translate = PromptBuilder().buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual, translationTargetLanguage: .ru, translate: true),
            context: PersonalizationContext(vocabulary: []),
            hints: hints
        )
        #expect(plain.advisory?.contains("so the output is still only the cleaned text):") == true)
        #expect(translate.advisory?.contains("so the output is still only the translated text):") == true)
    }
}
