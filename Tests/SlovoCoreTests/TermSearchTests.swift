import Foundation
import Testing

@testable import SlovoCore

// Term identity and word-boundary containment. Contract: term key = NFC + lowercase +
// collapsed whitespace runs (which subsumes trimming); boundary = adjacent scalars are
// neither letters nor digits; interior punctuation matches literally.
@Suite("Term search: keys and containment")
struct TermSearchKeyTests {
    /// Stated sensitivity: drop `.lowercased()` from `fold` → keys differ → RED.
    @Test
    func caseVariantsFoldToOneKey() {
        #expect(TermSearch.fold("Kubernetes") == TermSearch.fold("kubernetes"))
        #expect(TermSearch.fold("  GitHub \n") == "github")
    }

    /// NFC: a decomposed "й" (и + combining breve) and the precomposed form are one key.
    /// Compared as UTF-8 BYTES, not as `String`: Swift's `==` already compares
    /// canonically, so a String assertion here can never fail and would pin
    /// nothing. SQLite compares `term_key` bytewise, so the normalization is
    /// what actually makes the two forms one row.
    /// Stated sensitivity: drop `.precomposedStringWithCanonicalMapping` from
    /// `normalize` → the byte arrays differ → RED.
    @Test
    func canonicalCompositionIsNormalized() {
        let decomposed = "и\u{0306}ота"
        let precomposed = "йота"
        #expect(
            Array(TermSearch.fold(decomposed).utf8)
                == Array(TermSearch.fold(precomposed).utf8)
        )
    }

    /// "cat" must not be found inside "catalog"; a standalone occurrence is found.
    /// Stated sensitivity: remove the boundary checks in `contains` (plain
    /// substring search) → "catalog" case matches → RED.
    @Test
    func wordBoundariesRejectSubstrings() {
        let text = TermSearch.fold("the catalog lists a cat")
        #expect(TermSearch.contains("cat", in: text))
        let onlyCatalog = TermSearch.fold("the catalog is long")
        #expect(!TermSearch.contains("cat", in: onlyCatalog))
    }

    /// Interior punctuation is literal: `node.js`, `a/b testing`, `rcv-web-ui`
    /// match as single units (53 multi-word terms live in the shipped DB).
    /// Stated sensitivity: tokenize the text on punctuation before matching →
    /// "node.js" can no longer match as a unit → RED.
    @Test
    func interiorPunctuationMatchesLiterally() {
        let text = TermSearch.fold("deploy rcv-web-ui, then Node.js (A/B testing)")
        #expect(TermSearch.contains("rcv-web-ui", in: text))
        #expect(TermSearch.contains("node.js", in: text))
        #expect(TermSearch.contains("a/b testing", in: text))
        // "ode.js" is preceded by "n", a letter — the left boundary fails.
        // (A bare "node" WOULD match before the dot: "." is a valid boundary
        // under the spec's rule; do not "fix" that by requiring whitespace.)
        #expect(!TermSearch.contains("ode.js", in: text))
    }

    /// Whitespace runs (newlines, doubles) fold to single spaces so multi-word
    /// terms match across line breaks.
    /// Stated sensitivity: make `fold` lowercase-only → the
    /// newline-split phrase no longer matches → RED.
    @Test
    func whitespaceRunsFoldToSingleSpaces() {
        let text = TermSearch.fold("uses  A/B\ntesting daily")
        #expect(TermSearch.contains("a/b testing", in: text))
    }
}

// Fuzzy near-match: ICU Any-Latin fold + windowed Levenshtein, gated to
// folded keys of >= 5 characters. Threshold: foldedLength / 3,
// integer division.
@Suite("Term search: fuzzy near-match")
struct TermSearchFuzzyTests {
    /// Folds `raw` the way term-miss detection does once per dictation, so each case reads
    /// as one key/transcript pair.
    private static func hasNearMatch(ofKey key: String, inRaw raw: String) -> Bool {
        TermSearch.nearMatch(ofKey: key, inRawTokens: TermSearch.latinTokens(inRaw: raw)) == .match
    }

    /// Cross-script correction evidence: «гитхаб» in raw is a 1-edit
    /// neighbor of key "github" after the latin fold.
    /// Stated sensitivity: remove `applyingTransform(.toLatin)` from
    /// `latinFold` → scripts never meet → RED.
    @Test
    func crossScriptNearMatchIsFound() {
        #expect(Self.hasNearMatch(ofKey: "github", inRaw: "залей это на гитхаб пожалуйста"))
    }

    /// THE gate test: a short acronym must never fuzzy-match its one-edit
    /// neighbor — a false miss promotes into a ~6-slot head, the expensive error.
    /// "rcv" (3 chars) vs raw "RSV" must yield NO near-match.
    /// Stated sensitivity: delete the `fuzzyGateMinimumLength` guard → "rsv"
    /// is 1 edit from "rcv", threshold 3/3 = 1 → match → RED.
    @Test
    func shortKeysNeverFuzzyMatch() {
        #expect(!Self.hasNearMatch(ofKey: "rcv", inRaw: "the rsv meeting is at noon"))
        #expect(!Self.hasNearMatch(ofKey: "оауф", inRaw: "включи oauth в настройках"))
    }

    /// Threshold edges under integer division: length 5 → 1 edit; length 6 →
    /// 2 edits. This test pins the DIVISOR.
    /// Stated sensitivity: flip `/ 3` to `/ 4` → the length-6 two-edit case
    /// fails → RED.
    @Test
    func thresholdFollowsIntegerDivision() {
        // "argus" (5) vs "argos" — 1 edit: within threshold 1.
        #expect(Self.hasNearMatch(ofKey: "argus", inRaw: "call argos now"))
        // "argus" vs "orgos" — 2 edits: beyond threshold 1.
        #expect(!Self.hasNearMatch(ofKey: "argus", inRaw: "call orgos now"))
        // "github" (6) vs "gethab" — 2 edits: within threshold 2.
        #expect(Self.hasNearMatch(ofKey: "github", inRaw: "open gethab today"))
    }

    /// Multi-word keys slide a ±1 token window: "wispr flow" matches the
    /// two-token mangling "wisper floh" and the one-token "wisprflow".
    /// Stated sensitivity: fix the window size to exactly the key's token
    /// count → the one-token variant no longer matches → RED.
    @Test
    func multiWordKeysUseTokenWindows() {
        #expect(Self.hasNearMatch(ofKey: "wispr flow", inRaw: "открой wisper floh сейчас"))
        #expect(Self.hasNearMatch(ofKey: "wispr flow", inRaw: "запусти wisprflow опять"))
    }

    /// An accepted limitation, pinned so a "fix" is a conscious decision:
    /// phonetic respelling "джитхаб" folds to "džithab" → "dzithab", 3 edits
    /// from "github" over threshold 2 → NO match.
    /// Stated sensitivity: raise the threshold to length/2 → matches → RED.
    @Test
    func phoneticRespellingBeyondThresholdIsSkipped() {
        #expect(!Self.hasNearMatch(ofKey: "github", inRaw: "залей на джитхаб"))
    }
}
