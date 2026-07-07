import Testing

import SlovoCore

// The Whisper bias prompt must be budgeted to the model's
// prefix-token limit. After the 201-term vocabulary import the top-N terms are
// tokenized and passed UNCAPPED into DecodingOptions.promptTokens; Whisper's
// decoder context is 448 tokens (usable prompt/prefix share ~224) and we send
// ~500+, degrading live dictation. The fix budgets greedily by input order (terms
// arrive weight-sorted desc) inside WhisperKitBiasPromptBuilder.promptTokens.
@Suite("Whisper bias prompt token budget")
struct WhisperKitBiasPromptBuilderTests {
    // Alias to the production budget so the assertions track the grounded value
    // (WhisperKitBiasPromptBuilder.promptTokenBudget, cited in the builder from the
    // WhisperKit/Whisper decoder-context docs) rather than a brittle literal.
    private static let promptTokenBudget = WhisperKitBiasPromptBuilder.promptTokenBudget

    /// A deterministic fake tokenizer: one token per whitespace/newline-separated
    /// word, the id a stable per-word hash. It is ADDITIVE across lines — tokenizing
    /// the join of the first K lines equals concatenating each line's tokens — so a
    /// budgeted head-prefix of lines is a genuine prefix of the full token sequence,
    /// independent of whether the builder tokenizes per line or the whole join.
    private static func fakeTokenizer(_ text: String) -> [Int] {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" })
            .map { word in word.unicodeScalars.reduce(0) { ($0 &* 131 &+ Int($1.value)) & 0xFF_FFFF } }
    }

    /// Many long terms must be capped to the prefix budget, not sent whole.
    /// Killing mutation: remove the cap — the uncapped join is ~10x the budget, so
    /// the count exceeds the budget -> RED (this is the live regression).
    @Test
    func manyTermsAreBudgetedToPrefixLimit() {
        let terms = (0..<60).map { index in
            Term(
                term: "term\(index)",
                expansion: "alpha beta gamma delta epsilon zeta eta theta iota",
                lang: .en,
                weight: 60 - index
            )
        }

        let tokens = WhisperKitBiasPromptBuilder.promptTokens(for: terms, tokenizer: Self.fakeTokenizer) ?? []

        #expect(!tokens.isEmpty, "a non-empty vocabulary must still yield a bias prompt")
        #expect(tokens.count <= Self.promptTokenBudget,
                "prompt tokens must be budgeted to the Whisper prefix limit; got \(tokens.count) > \(Self.promptTokenBudget)")
    }

    /// The budget keeps the highest-weight HEAD (terms arrive weight-desc) and drops
    /// the tail at a line boundary — no reordering, no mid-list holes.
    /// Killing mutation: dropping from the head, reordering, or leaving a hole makes
    /// the surviving tokens not a head-prefix of the full sequence -> RED. On the
    /// current uncapped builder nothing is dropped, so `capped == full` -> RED.
    @Test
    func budgetKeepsHighestWeightHead() {
        let terms = (0..<60).map { index in
            Term(
                term: "head\(index)",
                expansion: (0..<9).map { "w\(index)_\($0)" }.joined(separator: " "),
                lang: .en,
                weight: 60 - index
            )
        }

        let capped = WhisperKitBiasPromptBuilder.promptTokens(for: terms, tokenizer: Self.fakeTokenizer) ?? []

        // Ground-truth line boundaries come from the builder's own (uncapped) prompt
        // join, so this pins budgeting behavior without re-deriving the line format.
        let promptLines = (WhisperKitBiasPromptBuilder.prompt(for: terms) ?? "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let headPrefixes = (1...promptLines.count).map { keep in
            Self.fakeTokenizer(promptLines.prefix(keep).joined(separator: "\n"))
        }
        let full = headPrefixes[headPrefixes.count - 1]

        #expect(!capped.isEmpty, "the budgeted head must survive")
        #expect(capped != full, "the tail must be dropped once the vocabulary exceeds the budget")
        #expect(headPrefixes.contains(capped),
                "surviving tokens must be exactly the first K lines (weight order kept, tail dropped, no holes); got count \(capped.count)")
    }

    /// A vocabulary sitting JUST BELOW the budget must be tokenized unchanged — the
    /// same output as the uncapped join. Regression guard (GREEN now).
    /// Sensitivity: the fixture is deliberately a few tokens under promptTokenBudget
    /// (not a trivial 3-token case), so a moderately over-eager cap — any budget
    /// lower than this fixture — truncates it and the assertion goes RED.
    @Test
    func underBudgetVocabularyIsUnchanged() {
        // 15 lines × 6 tokens = 90 tokens, just under the budget, so the whole
        // vocabulary must survive untouched.
        let terms = (0..<15).map { index in
            Term(term: "u\(index)", expansion: "alpha beta gamma delta epsilon", lang: .en, weight: 15 - index)
        }

        let expected = WhisperKitBiasPromptBuilder.prompt(for: terms).map(Self.fakeTokenizer)
        let capped = WhisperKitBiasPromptBuilder.promptTokens(for: terms, tokenizer: Self.fakeTokenizer)

        let expectedCount = expected?.count ?? 0
        #expect(expectedCount < Self.promptTokenBudget && expectedCount >= Self.promptTokenBudget - 10,
                "fixture must sit JUST below the budget to catch an over-eager cap; got \(expectedCount) vs budget \(Self.promptTokenBudget)")
        #expect(capped == expected,
                "an under-budget vocabulary must be tokenized unchanged; got \(String(describing: capped))")
    }

    /// Empty vocabulary, or a tokenizer that emits nothing, must collapse to nil —
    /// no bias prompt rather than an empty one. (GREEN now.)
    /// Sensitivity: returning an empty array instead of nil -> RED.
    @Test
    func emptyOrUntokenizableVocabularyYieldsNil() {
        #expect(WhisperKitBiasPromptBuilder.promptTokens(for: [], tokenizer: Self.fakeTokenizer) == nil,
                "no vocabulary must yield no bias prompt")

        let oneTerm = [Term(term: "x", expansion: nil, lang: .en, weight: 1)]
        #expect(WhisperKitBiasPromptBuilder.promptTokens(for: oneTerm, tokenizer: { _ in [] }) == nil,
                "an empty tokenization must collapse to nil, not an empty token array")
    }
}
