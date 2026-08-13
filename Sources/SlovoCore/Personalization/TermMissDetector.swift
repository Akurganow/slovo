import Foundation

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
/// One `fold` serves both roles: it turns a vocabulary surface into its event
/// identity ("key") and a transcript into matchable text. Folding both sides
/// the same way is what lets a key be searched inside a transcript at all, and
/// it means a surface stored with stray or doubled whitespace still matches.
enum TermMissDetector {
    /// NFC + lowercase + whitespace runs collapsed to single spaces (which
    /// subsumes trimming). As a term key this collapses case-variant vocabulary
    /// rows onto one statistic — matching, and via NFC slightly stronger than,
    /// the bias head's own case-insensitive collapsing.
    static func fold(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Whether `key` occurs in `foldedText` at word boundaries: the scalars
    /// adjacent to the match are neither letters nor digits. Interior
    /// punctuation ("node.js", "a/b testing") matches literally.
    static func containsKey(_ key: String, in foldedText: String) -> Bool {
        guard !key.isEmpty else { return false }
        var searchRange = foldedText.startIndex..<foldedText.endIndex
        while let match = foldedText.range(of: key, range: searchRange) {
            if isBoundary(before: match.lowerBound, in: foldedText),
               isBoundary(after: match.upperBound, in: foldedText) {
                return true
            }
            guard match.lowerBound < foldedText.endIndex else { break }
            searchRange = foldedText.index(after: match.lowerBound)..<foldedText.endIndex
        }
        return false
    }

    private static func isBoundary(before index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return true }
        return !isAlphanumeric(text[text.index(before: index)])
    }

    private static func isBoundary(after index: String.Index, in text: String) -> Bool {
        guard index < text.endIndex else { return true }
        return !isAlphanumeric(text[index])
    }

    private static func isAlphanumeric(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// Fuzzy matching is gated to folded keys of at least this many characters:
    /// below it one edit distance reaches unrelated words ("rcv" ↔ "rsv"), and
    /// a false miss is the expensive error — it evicts a term that needed help
    /// from the ~6-slot bias head. Short terms contribute no miss events; the
    /// gate's cost is reported as `shortTermSkippedCount`.
    static let fuzzyGateMinimumLength = 5

    /// Why the fuzzy pass produced no miss — a gate skip is counted apart from
    /// a genuine no-match, which feeds the never-introduce audit.
    enum NearMatchOutcome: Equatable {
        case match
        case noMatch
        case skippedShortKey
    }

    /// Script-agnostic fold: ICU Any-Latin transliteration, diacritics
    /// stripped, lowercased. "РСВ" → "rsv", "гитхаб" → "githab".
    static func latinFold(_ text: String) -> String {
        let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
        return latin.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// The raw transcript as latin-folded whitespace tokens. Computed once per
    /// dictation and reused for every candidate term — the transliteration is
    /// the expensive half of the fuzzy pass.
    static func latinTokens(inRaw raw: String) -> [String] {
        latinFold(fold(raw))
            .split(separator: " ")
            .map(String.init)
    }

    /// Whether a window of `tokens` (the key's token count ±1) lies within
    /// Levenshtein distance `foldedKeyLength / 3` of the latin-folded key. The
    /// ≥5 gate guarantees that threshold is at least 1.
    static func nearMatch(ofKey key: String, inRawTokens tokens: [String]) -> NearMatchOutcome {
        let foldedKey = latinFold(key)
        guard foldedKey.count >= fuzzyGateMinimumLength else { return .skippedShortKey }
        guard !tokens.isEmpty else { return .noMatch }
        let threshold = foldedKey.count / 3
        let keyTokenCount = max(1, foldedKey.split(separator: " ").count)
        let smallest = max(1, keyTokenCount - 1)
        for windowSize in smallest...(keyTokenCount + 1) where windowSize <= tokens.count {
            for start in 0...(tokens.count - windowSize) {
                let window = tokens[start..<(start + windowSize)].joined(separator: " ")
                if levenshtein(foldedKey, window) <= threshold { return .match }
            }
        }
        return .noMatch
    }

    /// The test-facing entry point: folds `raw` itself so a single key/transcript
    /// pair reads as one call. Detection always goes through `nearMatch`, which
    /// takes tokens folded once per dictation, so this has no production caller.
    static func hasNearMatch(ofKey key: String, inRaw raw: String) -> Bool {
        nearMatch(ofKey: key, inRawTokens: latinTokens(inRaw: raw)) == .match
    }

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
        let foldedRaw = fold(raw)
        let foldedCleaned = fold(cleaned)
        let rawTokens = latinTokens(inRaw: raw)
        var seenKeys: Set<String> = []
        var missKeys: [String] = []
        var unmatchedTermCount = 0
        var shortTermSkippedCount = 0
        for term in vocabulary {
            let key = fold(term.term)
            guard !key.isEmpty, seenKeys.insert(key).inserted else { continue }
            if containsKey(key, in: foldedRaw) { continue }
            guard containsKey(key, in: foldedCleaned) else { continue }
            switch nearMatch(ofKey: key, inRawTokens: rawTokens) {
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

    /// Classic two-row dynamic-programming edit distance over characters.
    static func levenshtein(_ source: String, _ target: String) -> Int {
        let left = Array(source), right = Array(target)
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }
        var previous = Array(0...right.count)
        var current = [Int](repeating: 0, count: right.count + 1)
        for row in 1...left.count {
            current[0] = row
            for column in 1...right.count {
                let substitution = previous[column - 1] + (left[row - 1] == right[column - 1] ? 0 : 1)
                current[column] = min(previous[column] + 1, current[column - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[right.count]
    }
}
