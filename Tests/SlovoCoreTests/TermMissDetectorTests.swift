import Foundation
import Testing

@testable import SlovoCore

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

    /// Stated sensitivity: drop the `seen` dedup set → two identical misses → RED.
    @Test
    func caseVariantRowsProduceOneEvent() {
        let detection = TermMissDetector.detectMisses(
            raw: "напиши кубернетес в чат",
            cleaned: "Напиши Kubernetes в чат.",
            vocabulary: [term("Kubernetes", weight: 4), term("kubernetes", weight: 3)]
        )
        #expect(detection.missKeys == ["kubernetes"])
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
