import Foundation

/// Turns the menu's comma-separated quick-add input into `vocabulary` rows.
///
/// User-added terms get category `term`, source `manual`, and weight 3 — above
/// bulk-imported rows (1–2) so they reliably reach the cleanup prompt's top-N,
/// below identity anchors (4–5).
public enum VocabularyQuickAdd {
    public static let category = "term"
    public static let source = "manual"
    public static let weight = 3

    /// Splits on commas, trims whitespace, drops empties, and de-duplicates
    /// case-insensitively keeping the first spelling.
    public static func parseTerms(_ input: String) -> [String] {
        var seen = Set<String>()
        return input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    public static func records(from input: String) -> [VocabularyRecord] {
        parseTerms(input).map { term in
            VocabularyRecord(term: term, category: category, source: source, weight: weight)
        }
    }
}
