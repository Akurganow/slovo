import Foundation

/// Finds a vocabulary term in text at word boundaries, exactly (`fold`, `contains`)
/// and approximately across scripts (`latinFold`, `nearMatch`). Term-miss detection
/// and the cleanup prompt both use it.
enum TermSearch {
    /// NFC + whitespace runs collapsed to single spaces (which subsumes
    /// trimming), letter case kept.
    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// `normalize` + lowercase. As a term key this collapses case-variant vocabulary
    /// rows onto one statistic — matching, and via NFC slightly stronger than,
    /// the bias head's own case-insensitive collapsing.
    static func fold(_ text: String) -> String {
        normalize(text).lowercased()
    }

    /// Whether `key` occurs in `text` at word boundaries: the scalars
    /// adjacent to the match are neither letters nor digits. Interior
    /// punctuation ("node.js", "a/b testing") matches literally.
    static func contains(_ key: String, in text: String) -> Bool {
        firstMatch(of: key, in: text) != nil
    }

    /// The first word-boundary occurrence of `key` in `text`, compared literally:
    /// fold both sides for a case-insensitive search, normalize both for a
    /// case-sensitive one.
    static func firstMatch(of key: String, in text: String) -> Range<String.Index>? {
        guard !key.isEmpty else { return nil }
        var searchRange = text.startIndex..<text.endIndex
        while let match = text.range(of: key, range: searchRange) {
            if isBoundary(before: match.lowerBound, in: text),
               isBoundary(after: match.upperBound, in: text) {
                return match
            }
            guard match.lowerBound < text.endIndex else { break }
            searchRange = text.index(after: match.lowerBound)..<text.endIndex
        }
        return nil
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
