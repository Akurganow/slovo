import Foundation

/// The single owner of the bias-rank formula:
/// `score = weight + missBoost · Σ 0.5^(age / halfLife)`.
/// Pure — callers fetch events and supply `now`, so tests need no database.
/// Eviction is decay: misses only ADD (every score >= its weight, manual
/// ordering survives untouched terms), and a fixed term's boost halves every
/// `halfLife` until its slot frees itself. No demotion mechanism exists, so
/// no promote/fix/evict oscillation can.
enum BiasRanker {
    /// One fresh miss outranks one manual weight step (weights span 1–5):
    /// the head chases failures by design.
    static let missBoost: Double = 2
    static let halfLife: TimeInterval = 14 * 86_400

    static func score(weight: Int, missDates: [Date], now: Date) -> Double {
        let missMass = missDates.reduce(0.0) { total, date in
            let age = max(0, now.timeIntervalSince(date))
            return total + pow(0.5, age / halfLife)
        }
        return Double(weight) + missBoost * missMass
    }

    /// Orders terms by (score desc, weight desc, term asc). The weight
    /// tie-break keeps the manual order among terms with equal scores.
    ///
    /// The final tie-break is TOTAL by scalar, not `<` (the
    /// `PromptBuilder` precedent): Swift's sort is not contractually stable, so
    /// a comparator reporting equality for two canonically-equivalent-but-byte-
    /// different terms would let them swap between runs — and this order decides
    /// which terms reach the bias head.
    static func rank(_ terms: [Term], missDates: [String: [Date]], now: Date) -> [Term] {
        terms
            .map { term in
                (term: term, score: score(
                    weight: term.weight,
                    missDates: missDates[TermMissDetector.fold(term.term)] ?? [],
                    now: now
                ))
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.term.weight != rhs.term.weight { return lhs.term.weight > rhs.term.weight }
                return lhs.term.term.unicodeScalars.lexicographicallyPrecedes(rhs.term.term.unicodeScalars)
            }
            .map(\.term)
    }
}
