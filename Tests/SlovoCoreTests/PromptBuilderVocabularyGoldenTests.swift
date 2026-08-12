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
    private static func blocks(hints: CleanupHints = CleanupHints()) -> [String] {
        PromptBuilder(maxVocabularyTerms: 3).buildPrompt(
            raw: "hello",
            config: CleanupConfig(writingStyle: .casual, language: .auto),
            context: PersonalizationContext(vocabulary: [
                Term(term: "RCV", expansion: "RingCentral Video", lang: .en, weight: 9),
            ]),
            hints: hints
        ).systemBlocks
    }

    /// The block's tags, line order, and line separation are its contract, not merely
    /// the presence of each line — and it is ONE system block of its own, emitted once.
    /// Stated sensitivity: collapse the newline join, glue the tags to the content,
    /// mangle either tag, reorder the lines, emit the block twice, emit it before the
    /// instructions, or fold it into `systemBlocks[0]` → RED.
    @Test
    func vocabularyBlockMatchesGoldenLiteral() {
        let blocks = Self.blocks()

        #expect(blocks.count == 2, "the vocabulary block is its own system block, emitted exactly once")
        #expect(blocks.last == Self.goldenVocabularyBlock)
    }

    /// Block order is the prompt's cache prefix: the stable instruction block first, then
    /// the slow-moving vocabulary, then the per-dictation advisory.
    /// Stated sensitivity: append the advisory before the vocabulary block → the
    /// per-index expectations redden.
    @Test
    func vocabularyPrecedesTheAdvisoryBlock() {
        let blocks = Self.blocks(hints: CleanupHints(inputLocale: "ru"))

        #expect(blocks.count == 3)
        if blocks.count == 3 {
            #expect(blocks[0].hasPrefix("<role>"))
            #expect(blocks[1] == Self.goldenVocabularyBlock)
            #expect(blocks[2].hasPrefix("<advisory>"))
        }
    }

    private static let goldenVocabularyBlock = [
        "<vocabulary>",
        "Correct spellings of the speaker's terms, each with its recorded meaning in parentheses where known: RCV (RingCentral Video)",
        "Preserve these terms verbatim wherever the transcript already spells them correctly.",
        "If the transcript contains a phonetic or transliterated mis-recognition of one of these terms "
            + "— a Cyrillic rendering of a Latin acronym, a split-apart or wrongly cased form — "
            + "replace it with the spelling given here.",
        PromptBuilderFixtures.parentheticalGuardLine,
        "Never introduce a term from this list that the speaker did not say.",
        "</vocabulary>",
    ].joined(separator: "\n")
}
