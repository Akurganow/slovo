import Testing

import SlovoCore

// The byte-exact VOCABULARY system block — the third pinned block beside the plain and
// translate rule goldens. The literal is authored independently, NOT copied from the
// builder's own output, so it pins drift and mutation rather than tautologically
// mirroring the implementation under test. Unlike its two siblings it is assembled from
// per-line literals: one rule line exceeds the 160-char source-line convention, and the
// newline join is itself part of what the comparison pins.
@Suite("Cleanup prompt vocabulary golden")
struct PromptBuilderVocabularyGoldenTests {
    private static func prompt(hints: CleanupHints = CleanupHints()) -> CleanupPrompt {
        PromptBuilder().buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual),
            context: PersonalizationContext(vocabulary: [
                Term(term: "RCV", expansion: "RingCentral Video", lang: .en, weight: 9),
            ]),
            hints: hints
        )
    }

    /// The block's tags, line order, and line separation are its contract, not merely
    /// the presence of each line — and it is ONE system block of its own, emitted once.
    /// Stated sensitivity: collapse the newline join, glue the tags to the content,
    /// mangle either tag, reorder the lines, change the licence line's wording, emit the
    /// block twice, emit it before the instructions, or fold it into `prefixBlocks[0]` → RED.
    @Test
    func vocabularyBlockMatchesGoldenLiteral() {
        let blocks = Self.prompt().prefixBlocks

        #expect(blocks.count == 2, "the vocabulary block is its own system block, emitted exactly once")
        #expect(blocks.last == Self.goldenVocabularyBlock)
    }

    /// Block order is the prompt's cache prefix: the stable instruction block first, then
    /// the slow-moving vocabulary; the per-dictation advisory is outside the prefix.
    /// Stated sensitivity: put the advisory into `prefixBlocks` (before or after the
    /// vocabulary), or the vocabulary before the instructions → the expectations redden.
    @Test
    func vocabularyFollowsTheInstructionsAndTheAdvisoryStaysOutsideThePrefix() {
        let prompt = Self.prompt(hints: CleanupHints(inputLocale: "ru"))

        #expect(prompt.prefixBlocks.count == 2)
        if prompt.prefixBlocks.count == 2 {
            #expect(prompt.prefixBlocks[0].hasPrefix("<role>"))
            #expect(prompt.prefixBlocks[1] == Self.goldenVocabularyBlock)
        }
        #expect(prompt.advisory?.hasPrefix("<advisory>") == true)
    }

    private static let goldenVocabularyBlock = [
        "<vocabulary>",
        "Correct spellings of the speaker's terms, each with its recorded meaning in parentheses where known: RCV (RingCentral Video)",
        "Preserve these terms verbatim wherever the transcript already spells them correctly.",
        "If the transcript contains a phonetic or transliterated mis-recognition of one of these terms "
            + "— a Cyrillic rendering of a Latin acronym, a split-apart form, or a wrongly cased form "
            + "that is not an ordinary word — "
            + "and the sentence uses it as that term, replace it with the spelling given here.",
        "An ordinary word in its everyday sense is never replaced with a listed term, even when it matches one.",
        PromptBuilderFixtures.parentheticalGuardLine,
        "Never introduce a term from this list that the speaker did not say.",
        "</vocabulary>",
    ].joined(separator: "\n")
}
