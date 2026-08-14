import Foundation
import Testing

@testable import SlovoCore

// score = weight + 2·M, M = Σ 0.5^(age/14d); ordering (score desc,
// weight desc, term asc). Spec section "Ranking".
@Suite("Bias ranker")
struct BiasRankerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func term(_ surface: String, weight: Int) -> Term {
        Term(term: surface, expansion: nil, lang: .en, weight: weight)
    }

    /// Decay pinning: a fresh miss adds 2.0, a 14-day-old one 1.0, a
    /// 28-day-old one 0.5.
    /// Stated sensitivity: change halfLife to 7 days → the 14-day case
    /// contributes 0.5 not 1.0 → RED.
    @Test
    func decayHalvesEveryFourteenDays() {
        let fresh = BiasRanker.score(weight: 1, missDates: [now], now: now)
        #expect(abs(fresh - 3.0) < 0.0001)
        let fortnight = BiasRanker.score(weight: 1, missDates: [now.addingTimeInterval(-14 * 86_400)], now: now)
        #expect(abs(fortnight - 2.0) < 0.0001)
        let month = BiasRanker.score(weight: 1, missDates: [now.addingTimeInterval(-28 * 86_400)], now: now)
        #expect(abs(month - 1.5) < 0.0001)
    }

    /// Misses only add: every score >= its weight, so the manual order
    /// survives wherever no miss intervenes (no floor needed).
    /// Stated sensitivity: subtract instead of add in `score` → RED.
    @Test
    func scoreNeverDropsBelowWeight() {
        let score = BiasRanker.score(
            weight: 5,
            missDates: [now.addingTimeInterval(-365 * 86_400)],
            now: now
        )
        #expect(score >= 5.0)
    }

    /// A future-dated event (clock skew) is clamped, not amplified — spec
    /// section Ranking: "event ages clamp at zero".
    /// Stated sensitivity: drop the `max(0, age)` clamp → 0.5^negative > 1
    /// inflates the score above 3.0 → RED.
    @Test
    func futureDatesAreClamped() {
        let score = BiasRanker.score(weight: 1, missDates: [now.addingTimeInterval(86_400)], now: now)
        #expect(abs(score - 3.0) < 0.0001)
    }

    /// One fresh miss (+2) lifts a weight-1 term past a weight-2 peer —
    /// the head chases failures.
    /// Stated sensitivity: set missBoost to 0.5 → weight-2 stays ahead → RED.
    @Test
    func freshMissOutranksOneWeightStep() {
        let ranked = BiasRanker.rank(
            [term("stable", weight: 2), term("missed", weight: 1)],
            missDates: ["missed": [now]],
            now: now
        )
        #expect(ranked.map(\.term) == ["missed", "stable"])
    }

    /// Ties break by weight desc, then term asc — the manual order among
    /// untouched terms is preserved verbatim, never alphabetized.
    ///
    /// The no-events fixture alone CANNOT pin the weight tie-break: with no
    /// misses every score equals its weight, so the score comparator already
    /// reproduces this order and removing the weight tie-break changes nothing.
    /// The second fixture manufactures a real score tie (1 + 2·1 == 3) across
    /// different weights, which is the only shape that reaches it.
    /// Stated sensitivity: remove the weight tie-break (score, term only) →
    /// the tied pair falls to the term comparator and returns
    /// ["alpha", "zulu"] → RED.
    @Test
    func tieBreaksByWeightThenTerm() {
        let ranked = BiasRanker.rank(
            [term("alpha", weight: 1), term("zulu", weight: 3), term("beta", weight: 3)],
            missDates: [:],
            now: now
        )
        #expect(ranked.map(\.term) == ["beta", "zulu", "alpha"])

        let tied = BiasRanker.rank(
            [term("alpha", weight: 1), term("zulu", weight: 3)],
            missDates: ["alpha": [now]],   // 1 + 2·1 = 3.0 ties zulu's 3.0
            now: now
        )
        #expect(tied.map(\.term) == ["zulu", "alpha"])
    }

    /// A total tie-break makes the ranking a function of the SET, independent of
    /// input order. Canonically equivalent, byte-different surfaces compare equal
    /// under `<` (canonical String comparison), which hands the unstable sort a
    /// free permutation; scalar-lexicographic comparison keeps the output fixed.
    /// Stated sensitivity: revert the tie-break to `String <` → forward and
    /// reversed runs disagree on the byte order of the equivalent pair → RED.
    @Test
    func equivalentSurfacesRankOrderIndependently() {
        let nfc = "йота"
        let nfd = "и\u{0306}ота"
        let forward = BiasRanker.rank([term(nfc, weight: 1), term(nfd, weight: 1)], missDates: [:], now: now)
        let reversed = BiasRanker.rank([term(nfd, weight: 1), term(nfc, weight: 1)], missDates: [:], now: now)
        #expect(forward.map { Array($0.term.utf8) } == reversed.map { Array($0.term.utf8) })
    }

    /// Miss dates are looked up by the FOLDED key: a "GitHub" term finds
    /// events stored under "github".
    /// Stated sensitivity: look up by the raw surface instead of
    /// `fold` → no boost → RED.
    @Test
    func lookupUsesFoldedKey() {
        let ranked = BiasRanker.rank(
            [term("stable", weight: 2), term("GitHub", weight: 1)],
            missDates: ["github": [now]],
            now: now
        )
        #expect(ranked.map(\.term) == ["GitHub", "stable"])
    }
}
