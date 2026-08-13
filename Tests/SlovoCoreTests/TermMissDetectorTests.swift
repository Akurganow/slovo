import Foundation
import Testing

@testable import SlovoCore

// Term identity and word-boundary containment for miss detection.
// Contract under test: docs/superpowers/specs/2026-08-13-vocab-usage-weighting-design.md,
// "Miss detection" — term key = NFC + lowercase + collapsed whitespace runs
// (which subsumes trimming); boundary = adjacent
// scalars are neither letters nor digits; interior punctuation matches literally.
@Suite("Term miss detector: keys and containment")
struct TermMissDetectorKeyTests {
    /// Case-variant vocabulary rows share one key — the live DB holds
    /// `Akurganow`/`akurganow` as two rows, one statistic.
    /// Stated sensitivity: drop `.lowercased()` from `fold` → keys differ → RED.
    @Test
    func caseVariantsFoldToOneKey() {
        #expect(TermMissDetector.fold("Akurganow") == TermMissDetector.fold("akurganow"))
        #expect(TermMissDetector.fold("  GitHub \n") == "github")
    }

    /// NFC: a decomposed "й" (и + combining breve) and the precomposed form are one key.
    /// Compared as UTF-8 BYTES, not as `String`: Swift's `==` already compares
    /// canonically, so a String assertion here can never fail and would pin
    /// nothing. SQLite compares `term_key` bytewise, so the normalization is
    /// what actually makes the two forms one row.
    /// Stated sensitivity: drop `.precomposedStringWithCanonicalMapping` from
    /// `fold` → the byte arrays differ → RED.
    @Test
    func canonicalCompositionIsNormalized() {
        let decomposed = "и\u{0306}ота"
        let precomposed = "йота"
        #expect(
            Array(TermMissDetector.fold(decomposed).utf8)
                == Array(TermMissDetector.fold(precomposed).utf8)
        )
    }

    /// "cat" must not be found inside "catalog"; a standalone occurrence is found.
    /// Stated sensitivity: remove the boundary checks in `containsKey` (plain
    /// substring search) → "catalog" case matches → RED.
    @Test
    func wordBoundariesRejectSubstrings() {
        let text = TermMissDetector.fold("the catalog lists a cat")
        #expect(TermMissDetector.containsKey("cat", in: text))
        let onlyCatalog = TermMissDetector.fold("the catalog is long")
        #expect(!TermMissDetector.containsKey("cat", in: onlyCatalog))
    }

    /// Interior punctuation is literal: `node.js`, `a/b testing`, `rcv-web-ui`
    /// match as single units (53 multi-word terms live in the shipped DB).
    /// Stated sensitivity: tokenize the text on punctuation before matching →
    /// "node.js" can no longer match as a unit → RED.
    @Test
    func interiorPunctuationMatchesLiterally() {
        let text = TermMissDetector.fold("deploy rcv-web-ui, then Node.js (A/B testing)")
        #expect(TermMissDetector.containsKey("rcv-web-ui", in: text))
        #expect(TermMissDetector.containsKey("node.js", in: text))
        #expect(TermMissDetector.containsKey("a/b testing", in: text))
        // "ode.js" is preceded by "n", a letter — the left boundary fails.
        // (A bare "node" WOULD match before the dot: "." is a valid boundary
        // under the spec's rule; do not "fix" that by requiring whitespace.)
        #expect(!TermMissDetector.containsKey("ode.js", in: text))
    }

    /// Whitespace runs (newlines, doubles) fold to single spaces so multi-word
    /// terms match across line breaks.
    /// Stated sensitivity: make `fold` lowercase-only → the
    /// newline-split phrase no longer matches → RED.
    @Test
    func whitespaceRunsFoldToSingleSpaces() {
        let text = TermMissDetector.fold("uses  A/B\ntesting daily")
        #expect(TermMissDetector.containsKey("a/b testing", in: text))
    }
}

// Fuzzy near-match: ICU Any-Latin fold + windowed Levenshtein, gated to
// folded keys of >= 5 characters. Threshold: foldedLength / 3,
// integer division. Spec section "Miss detection", rule 2.
@Suite("Term miss detector: fuzzy near-match")
struct TermMissDetectorFuzzyTests {
    /// Cross-script correction evidence: «гитхаб» in raw is a 1-edit
    /// neighbor of key "github" after the latin fold.
    /// Stated sensitivity: remove `applyingTransform(.toLatin)` from
    /// `latinFold` → scripts never meet → RED.
    @Test
    func crossScriptNearMatchIsFound() {
        #expect(TermMissDetector.hasNearMatch(ofKey: "github", inRaw: "залей это на гитхаб пожалуйста"))
    }

    /// THE gate test: a short acronym must never fuzzy-match its one-edit
    /// neighbor — a false miss promotes into a ~6-slot head, the expensive error.
    /// "rcv" (3 chars) vs raw "RSV" must yield NO near-match.
    /// Stated sensitivity: delete the `fuzzyGateMinimumLength` guard → "rsv"
    /// is 1 edit from "rcv", threshold 3/3 = 1 → match → RED.
    @Test
    func shortKeysNeverFuzzyMatch() {
        #expect(!TermMissDetector.hasNearMatch(ofKey: "rcv", inRaw: "the rsv meeting is at noon"))
        #expect(!TermMissDetector.hasNearMatch(ofKey: "оауф", inRaw: "включи oauth в настройках"))
    }

    /// Threshold edges under integer division: length 5 → 1 edit; length 6 →
    /// 2 edits. This test pins the DIVISOR.
    /// Stated sensitivity: flip `/ 3` to `/ 4` → the length-6 two-edit case
    /// fails → RED.
    @Test
    func thresholdFollowsIntegerDivision() {
        // "argus" (5) vs "argos" — 1 edit: within threshold 1.
        #expect(TermMissDetector.hasNearMatch(ofKey: "argus", inRaw: "call argos now"))
        // "argus" vs "orgos" — 2 edits: beyond threshold 1.
        #expect(!TermMissDetector.hasNearMatch(ofKey: "argus", inRaw: "call orgos now"))
        // "github" (6) vs "gethab" — 2 edits: within threshold 2.
        #expect(TermMissDetector.hasNearMatch(ofKey: "github", inRaw: "open gethab today"))
    }

    /// Multi-word keys slide a ±1 token window: "wispr flow" matches the
    /// two-token mangling "wisper floh" and the one-token "wisprflow".
    /// Stated sensitivity: fix the window size to exactly the key's token
    /// count → the one-token variant no longer matches → RED.
    @Test
    func multiWordKeysUseTokenWindows() {
        #expect(TermMissDetector.hasNearMatch(ofKey: "wispr flow", inRaw: "открой wisper floh сейчас"))
        #expect(TermMissDetector.hasNearMatch(ofKey: "wispr flow", inRaw: "запусти wisprflow опять"))
    }

    /// An accepted limitation, pinned so a "fix" is a conscious decision:
    /// phonetic respelling "джитхаб" folds to "džithab" → "dzithab", 3 edits
    /// from "github" over threshold 2 → NO match.
    /// Stated sensitivity: raise the threshold to length/2 → matches → RED.
    @Test
    func phoneticRespellingBeyondThresholdIsSkipped() {
        #expect(!TermMissDetector.hasNearMatch(ofKey: "github", inRaw: "залей на джитхаб"))
    }
}

// Full detection: rule 1 (in raw → nothing), rule 2 (in cleaned only →
// fuzzy-confirmed miss, else unmatched count), rule 3 (nowhere → nothing).
// Spec section "Miss detection".
@Suite("Term miss detector: detection")
struct TermMissDetectorDetectionTests {
    private func term(_ surface: String, weight: Int = 1) -> Term {
        Term(term: surface, expansion: nil, lang: .en, weight: weight)
    }

    /// The golden path: ASR mangled «гитхаб», the cleaner wrote "GitHub" —
    /// one miss under the folded key.
    /// Stated sensitivity: invert rule 2's raw-containment guard (record when
    /// the term IS in raw) → no miss here → RED.
    @Test
    func correctedManglingYieldsMiss() {
        let detection = TermMissDetector.detectMisses(
            raw: "залей это на гитхаб",
            cleaned: "Залей это на GitHub.",
            vocabulary: [term("GitHub")]
        )
        #expect(detection.missKeys == ["github"])
        #expect(detection.unmatchedTermCount == 0)
    }

    /// A term the ASR already got right produces nothing — v1 records no hits.
    /// Stated sensitivity: record a key for the in-raw branch → non-empty → RED.
    @Test
    func termPresentInRawYieldsNothing() {
        let detection = TermMissDetector.detectMisses(
            raw: "open github now",
            cleaned: "Open GitHub now.",
            vocabulary: [term("GitHub")]
        )
        #expect(detection == TermMissDetection(missKeys: [], unmatchedTermCount: 0, shortTermSkippedCount: 0))
    }

    /// Pass-through (cleaned == raw, the FallbackCleaner shape) yields zero
    /// events by construction.
    /// Stated sensitivity: relax rule 2 to "in cleaned" without the not-in-raw
    /// guard → misses appear → RED.
    @Test
    func passThroughYieldsNothing() {
        let text = "деплой rcv-web-ui сломан"
        let detection = TermMissDetector.detectMisses(
            raw: text, cleaned: text, vocabulary: [term("rcv-web-ui")]
        )
        #expect(detection == TermMissDetection(missKeys: [], unmatchedTermCount: 0, shortTermSkippedCount: 0))
    }

    /// A term in cleaned with NO near-match in raw is counted as unmatched
    /// (the never-introduce audit number) and records no miss.
    /// Stated sensitivity: append the key to `missKeys` on the no-near-match
    /// branch → missKeys non-empty → RED.
    @Test
    func introducedTermCountsAsUnmatchedOnly() {
        let detection = TermMissDetector.detectMisses(
            raw: "совершенно другой текст без похожих слов",
            cleaned: "Deploy it with Kubernetes.",
            vocabulary: [term("Kubernetes")]
        )
        #expect(detection.missKeys.isEmpty)
        #expect(detection.unmatchedTermCount == 1)
        // Long enough to clear the gate, so the absence is a real no-match.
        #expect(detection.shortTermSkippedCount == 0)
    }

    /// Case-variant vocabulary rows (live DB: Akurganow/akurganow) are
    /// processed once — one key, at most one event.
    /// Stated sensitivity: drop the `seen` dedup set → two identical misses → RED.
    @Test
    func caseVariantRowsProduceOneEvent() {
        let detection = TermMissDetector.detectMisses(
            raw: "напиши акурганов в чат",
            cleaned: "Напиши Akurganow в чат.",
            vocabulary: [term("Akurganow", weight: 4), term("akurganow", weight: 3)]
        )
        #expect(detection.missKeys == ["akurganow"])
    }

    /// A short key on the cleaned-only path records no miss and counts as
    /// GATE-SKIPPED, never as unmatched: the ≥5 gate refused to judge it, which
    /// is not evidence the cleaner introduced the term. Mixing the two would
    /// drown the never-introduce audit — roughly a quarter of the live
    /// vocabulary folds under 5 characters.
    /// Stated sensitivity: route gate-skipped terms into `unmatchedTermCount`
    /// (the pre-split behavior) → shortTermSkippedCount 0, unmatched 1 → RED.
    @Test
    func shortKeyOnCleanedPathCountsAsGateSkipped() {
        let detection = TermMissDetector.detectMisses(
            raw: "встреча про рсв завтра",   // cyrillic "рсв" ≠ latin key "rcv" for containment
            cleaned: "Встреча про RCV завтра.",
            vocabulary: [term("RCV")]
        )
        #expect(detection.missKeys.isEmpty)
        #expect(detection.shortTermSkippedCount == 1)
        #expect(detection.unmatchedTermCount == 0)
    }
}
