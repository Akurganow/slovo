/// One dictation's detection result: the folded keys of confirmed misses, plus
/// two coarse audit counts that are never stored — terms found only in the
/// cleaned text with no near-match in raw (`unmatchedTermCount`), and terms the
/// short-key gate refused to fuzzy-match at all (`shortTermSkippedCount`).
/// The two are separate so legitimate short corrections cannot drown the
/// never-introduce audit in noise.
struct TermMissDetection: Equatable, Sendable {
    let missKeys: [String]
    let unmatchedTermCount: Int
    let shortTermSkippedCount: Int
}

/// Pure detection of vocabulary-term ASR misses by comparing a raw transcript
/// with its cleanup output. No storage, no side effects — the orchestrator
/// feeds it and a `TermMissRecording` sink persists its result.
///
/// One `TermSearch.fold` serves both roles: it turns a vocabulary surface into its
/// event identity ("key") and a transcript into matchable text. Folding both sides
/// the same way is what lets a key be searched inside a transcript at all, and it
/// means a surface stored with stray or doubled whitespace still matches.
enum TermMissDetector {
    /// Classifies every vocabulary term against one dictation. Rule 1: found
    /// in raw → the ASR handled it, nothing recorded (v1 stores no hits).
    /// Rule 2: found only in cleaned → a fuzzy-confirmed near-match in raw is
    /// a miss (the cleaner fixed a mangling); otherwise the term bumps whichever
    /// audit count explains the absence. Rule 3: found nowhere → nothing.
    static func detectMisses(
        raw: String,
        cleaned: String,
        vocabulary: [Term]
    ) -> TermMissDetection {
        let foldedRaw = TermSearch.fold(raw)
        let foldedCleaned = TermSearch.fold(cleaned)
        let rawTokens = TermSearch.latinTokens(inRaw: raw)
        var seenKeys: Set<String> = []
        var missKeys: [String] = []
        var unmatchedTermCount = 0
        var shortTermSkippedCount = 0
        for term in vocabulary {
            let key = TermSearch.fold(term.term)
            guard !key.isEmpty, seenKeys.insert(key).inserted else { continue }
            if TermSearch.contains(key, in: foldedRaw) { continue }
            guard TermSearch.contains(key, in: foldedCleaned) else { continue }
            switch TermSearch.nearMatch(ofKey: key, inRawTokens: rawTokens) {
            case .match:
                missKeys.append(key)
            case .noMatch:
                unmatchedTermCount += 1
            case .skippedShortKey:
                shortTermSkippedCount += 1
            }
        }
        return TermMissDetection(
            missKeys: missKeys,
            unmatchedTermCount: unmatchedTermCount,
            shortTermSkippedCount: shortTermSkippedCount
        )
    }
}
