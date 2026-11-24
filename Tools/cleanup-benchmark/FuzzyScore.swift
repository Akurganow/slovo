import CleanupBenchmarkFuzz
import NaturalLanguage

/// The fuzzy coefficient: RapidFuzz `token_sort_ratio` between an output and its
/// reference, as a value in 0...1. Word order never changes it; a missing letter
/// or combining mark does.
enum FuzzyScore {
    /// First id handed to a `Character`. It sits above every Unicode code point, so
    /// RapidFuzz's `is_space` (a list of code points) never reads an id as whitespace.
    private static let firstID: UInt32 = 0x11_0000
    private static let spaceID: UInt32 = 0x20

    /// The best `tokenSort` over the references.
    static func best(_ output: String, _ references: [String]) -> Double {
        references.map { tokenSort(output, $0) }.max() ?? 0
    }

    static func tokenSort(_ lhs: String, _ rhs: String) -> Double {
        let leftWords = words(lhs)
        let rightWords = words(rhs)
        let ids = characterIDs(for: leftWords + rightWords)
        let left = sequence(of: leftWords, ids: ids)
        let right = sequence(of: rightWords, ids: ids)
        let score = left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                cleanup_benchmark_token_sort_ratio(
                    leftBuffer.baseAddress, leftBuffer.count,
                    rightBuffer.baseAddress, rightBuffer.count
                )
            }
        }
        return score / 100
    }

    /// Folded words of `text`: lowercase, `ё` as `е`, and every character that is
    /// not a letter, a number (Nd, Nl, No: `²`, `Ⅳ`, `½`) or a combining mark (Mn, Mc) turned into a space, then
    /// split by Apple's word tokenizer. Combining marks stay, so a Devanagari or
    /// Arabic letter with its marks stays one `Character`.
    static func words(_ text: String) -> [String] {
        let folded = String(String.UnicodeScalarView(
            text.lowercased().unicodeScalars.map { scalar in
                if scalar == "\u{0451}" { return "\u{0435}" }
                return isKept(scalar) ? scalar : " "
            }
        ))
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = folded
        return tokenizer.tokens(for: folded.startIndex..<folded.endIndex).map { String(folded[$0]) }
    }

    private static func isKept(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber, .nonspacingMark, .spacingMark:
            true
        default:
            false
        }
    }

    /// One id per distinct `Character`, assigned in order of the characters' scalar
    /// sequences, so the same pair of texts always gets the same ids.
    private static func characterIDs(for words: [String]) -> [Character: UInt32] {
        let distinct = Set(words.joined())
        let sorted = distinct.sorted { lhs, rhs in
            lhs.unicodeScalars.lexicographicallyPrecedes(rhs.unicodeScalars) { $0.value < $1.value }
        }
        return Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($1, firstID + UInt32($0)) })
    }

    private static func sequence(of words: [String], ids: [Character: UInt32]) -> [UInt32] {
        words
            .map { word in word.compactMap { ids[$0] } }
            .enumerated()
            .flatMap { index, word in index == 0 ? word : [spaceID] + word }
    }
}
