import Foundation
import GRDB

/// A `vocabulary` row (spec §18.4). Inserts use `INSERT OR IGNORE` so re-applying
/// a seed never duplicates and never throws on a `(term, category)` conflict — a
/// conflicting row is silently skipped.
public struct VocabularyRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var term: String
    public var expansion: String?
    public var lang: String
    public var category: String
    public var source: String
    public var weight: Int

    public static let databaseTableName = "vocabulary"

    /// `INSERT OR IGNORE`: a row conflicting on the `(term, category)` unique key
    /// is skipped rather than replaced or rejected (AC-4).
    public static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .ignore)

    enum CodingKeys: String, CodingKey {
        case id, term, expansion, lang, category, source, weight
    }

    public init(
        term: String,
        expansion: String? = nil,
        lang: String = "en",
        category: String,
        source: String = "manual",
        weight: Int = 1
    ) {
        self.id = nil
        self.term = term
        self.expansion = expansion
        self.lang = lang
        self.category = category
        self.source = source
        self.weight = weight
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        // Under `INSERT OR IGNORE` a skipped insert reports rowID 0; don't adopt a
        // bogus id for a row that wasn't actually inserted (P18).
        guard inserted.rowID != 0 else { return }
        id = inserted.rowID
    }
}
