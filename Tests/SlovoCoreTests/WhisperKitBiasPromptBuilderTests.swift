import Testing

@testable import SlovoCore

// The bias prompt is ONE line of bare term surface forms, budgeted to the decode
// loop's sampling headroom: WhisperKit spends prefill (prompt) tokens inside the
// same 223-iteration window budget as sampled output, so an oversized prompt
// truncates the transcript mid-window instead of merely biasing it.
@Suite("Whisper bias prompt")
struct WhisperKitBiasPromptBuilderTests {
    // Alias to the production budget so the fixtures below are derived from the
    // grounded value (its derivation is documented on the constant) rather than a
    // literal that would drift.
    private static let maxPromptTokens = WhisperKitBiasPromptBuilder.maxPromptTokens

    /// One token per whitespace-separated word, the id a stable per-word hash.
    /// With the production format ("a, b, c.") this makes the token count equal
    /// the term count, so budget arithmetic is exact.
    private static func wordTokenizer(_ text: String) -> [Int] {
        text.split(separator: " ")
            .map { word in word.unicodeScalars.reduce(0) { ($0 &* 131 &+ Int($1.value)) & 0xFF_FFFF } }
    }

    /// One token per character — a deliberately dense tokenization, so a single
    /// term can be driven over the budget.
    private static func characterTokenizer(_ text: String) -> [Int] {
        text.unicodeScalars.map { Int($0.value) }
    }

    /// The budget must leave the decode window the SAMPLING headroom its derivation
    /// claims — the binding property behind the constant, not the literal 24. Prefill
    /// tokens are spent inside the loop's 223-iteration cap, so what remains for
    /// sampled output is `223 - (budget + 5 special prefill)`; the derivation commits
    /// to 194, chosen to clear the ~143-178 a 30 s Russian window needs (150 wpm at
    /// ~2.38 tokens/word) with margin left over.
    /// Stated sensitivity: raising `maxPromptTokens` by even ONE token (25) leaves 193
    /// → RED. The weaker "still fits the 223 cap" form would have stayed green all the
    /// way to 40 — the value that leaves exactly 178 and erases the entire margin —
    /// and reddened only at 41. Every other test in this suite derives its fixtures
    /// from the constant, so this is the one assertion that constrains its value.
    @Test
    func budgetLeavesTheDecodeWindowItsSamplingHeadroom() {
        let specialPrefillTokens = 5
        let decodeLoopCap = 223
        let derivedSampledHeadroom = 194

        let sampledTokensLeft = decodeLoopCap - (Self.maxPromptTokens + specialPrefillTokens)

        #expect(sampledTokensLeft >= derivedSampledHeadroom,
                "the budget must leave the \(derivedSampledHeadroom) sampled tokens its derivation claims; got \(sampledTokensLeft)")
    }

    /// The prompt is a single line of bare surface forms joined with ", " and
    /// closed with a period — no frame word, no expansions, no newlines.
    /// Stated sensitivity: restore the v1 `"term expansion"` newline-joined lines,
    /// add a frame word, or drop the trailing period → the handed text differs → RED.
    @Test
    func promptIsOneLineOfBareCommaJoinedTerms() {
        let terms = [
            Term(term: "RCV", expansion: "RingCentral Video", lang: .en, weight: 3),
            Term(term: "GitHub", expansion: nil, lang: .en, weight: 2),
            Term(term: "OAuth", expansion: nil, lang: .en, weight: 1),
        ]
        var handed: [String] = []

        let tokens = WhisperKitBiasPromptBuilder.promptTokens(for: terms) { text in
            handed.append(text)
            return Self.wordTokenizer(text)
        }

        #expect(handed.last == "RCV, GitHub, OAuth.")
        #expect(handed.last?.contains("RingCentral") == false,
                "expansions belong to the cleanup prompt; the bias prompt carries surface forms only")
        #expect(tokens?.count == 3)
    }

    /// Blank terms are skipped and case-insensitive repeats collapse to their FIRST
    /// occurrence, keeping that occurrence's stored casing (terms arrive
    /// weight-descending, so the first spelling is the highest-weighted one).
    /// Stated sensitivity: drop the dedupe → "rcv"/"Rcv" reappear → RED; keep the
    /// LAST occurrence, or normalize the survivor's casing → "Rcv"/"rcv" is handed
    /// instead of "RCV" → RED; stop trimming → the blank term becomes an empty slot → RED.
    @Test
    func blankTermsAreSkippedAndCaseRepeatsKeepTheFirstSpelling() {
        let terms = [
            Term(term: " RCV ", expansion: nil, lang: .en, weight: 5),
            Term(term: "   ", expansion: nil, lang: .en, weight: 4),
            Term(term: "rcv", expansion: nil, lang: .en, weight: 3),
            Term(term: "Rcv", expansion: nil, lang: .en, weight: 2),
            Term(term: "GitHub", expansion: nil, lang: .en, weight: 1),
        ]
        var handed: [String] = []

        _ = WhisperKitBiasPromptBuilder.promptTokens(for: terms) { text in
            handed.append(text)
            return Self.wordTokenizer(text)
        }

        #expect(handed.last == "RCV, GitHub.")
    }

    /// An over-budget vocabulary is trimmed from the TAIL, so the highest-weight
    /// head survives — the SDK keeps only the `.suffix` of an over-budget prompt,
    /// which would discard exactly that head. Pins the RESULTING prompt, not how
    /// many times the tokenizer was consulted to reach it.
    /// Stated sensitivity: remove the budget loop → the over-budget list survives →
    /// RED; drop from the HEAD (`removeFirst`), reorder, or leave a mid-list hole →
    /// the returned tokens stop being the head-prefix prompt → RED.
    @Test
    func budgetDropsFromTheTailSoTheHighestWeightHeadSurvives() {
        let termCount = Self.maxPromptTokens + 6
        let terms = (0..<termCount).map { index in
            Term(term: "t\(index)", expansion: nil, lang: .en, weight: termCount - index)
        }

        let tokens = WhisperKitBiasPromptBuilder.promptTokens(for: terms, tokenizer: Self.wordTokenizer)

        // One token per term under this tokenizer, so the whole budget is spendable
        // on terms and the surviving prompt is exactly the first `maxPromptTokens`.
        let survivingHead = (0..<Self.maxPromptTokens).map { "t\($0)" }.joined(separator: ", ") + "."
        #expect(tokens == Self.wordTokenizer(survivingHead),
                "the surviving prompt must be the head-prefix glossary, tail dropped")
        #expect((tokens?.count ?? 0) <= Self.maxPromptTokens)
    }

    /// A single term that cannot fit the budget yields NO prompt: a prompt whose
    /// own head does not fit would be re-trimmed by the SDK anyway.
    /// Stated sensitivity: return the over-budget tokens (or their prefix) instead
    /// of nil → RED.
    @Test
    func aSingleTermOverTheBudgetYieldsNoPrompt() {
        let oversized = String(repeating: "z", count: Self.maxPromptTokens + 16)
        let terms = [Term(term: oversized, expansion: nil, lang: .en, weight: 1)]

        #expect(WhisperKitBiasPromptBuilder.promptTokens(for: terms, tokenizer: Self.characterTokenizer) == nil)
    }

    /// An empty vocabulary — or a tokenizer that yields nothing, which is what the
    /// engine's `tokenizer?.encode(text:) ?? []` produces before the tokenizer
    /// loads — collapses to nil, so the session runs unbiased rather than carrying
    /// an empty prompt.
    /// Stated sensitivity: return an empty array instead of nil in either case → RED.
    @Test
    func emptyVocabularyOrEmptyTokenizationYieldsNoPrompt() {
        #expect(WhisperKitBiasPromptBuilder.promptTokens(for: [], tokenizer: Self.wordTokenizer) == nil)

        let terms = [Term(term: "RCV", expansion: nil, lang: .en, weight: 1)]
        #expect(WhisperKitBiasPromptBuilder.promptTokens(for: terms, tokenizer: { _ in [] }) == nil)
    }

    /// The engine's decoding options must CARRY the built prompt into the streaming
    /// decode — the seam that silently passed nil while the whole suite stayed green.
    /// Stated sensitivity: hardcode `promptTokens: nil` in `decodingOptions`, or stop
    /// handing it the session's `biasTerms` → the biased expectation goes RED;
    /// synthesize a prompt for an empty vocabulary → the unbiased one goes RED.
    @Test
    func decodingOptionsCarryTheBiasPromptTokens() {
        let terms = [
            Term(term: "RCV", expansion: nil, lang: .en, weight: 2),
            Term(term: "GitHub", expansion: nil, lang: .en, weight: 1),
        ]

        let biased = WhisperKitEngine.decodingOptions(language: .auto, biasTerms: terms, tokenizer: Self.wordTokenizer)
        #expect(biased.promptTokens == Self.wordTokenizer("RCV, GitHub."),
                "the built bias prompt must reach DecodingOptions.promptTokens")

        let unbiased = WhisperKitEngine.decodingOptions(language: .auto, biasTerms: [], tokenizer: Self.wordTokenizer)
        #expect(unbiased.promptTokens == nil, "no vocabulary must keep the session unbiased")
    }
}
