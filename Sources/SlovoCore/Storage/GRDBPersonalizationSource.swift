import GRDB

/// The GRDB-backed `PersonalizationSource`. The only place
/// that reads the vocabulary table; also the menu quick-add's write path.
///
/// SECURITY: a DB-row value (a term, expansion, …) must NEVER reach the
/// log. Only coarse counts cross into `RedactionSafeLog` — never a row payload.
public struct GRDBPersonalizationSource: PersonalizationSource {
    private let database: DatabasePool
    private let log: RedactionSafeLog

    public init(
        database: DatabasePool,
        log: RedactionSafeLog = RedactionSafeLog(subsystem: "slovo", category: "storage")
    ) {
        self.database = database
        self.log = log
    }

    /// Inserts user-added rows with `INSERT OR IGNORE` (the record's conflict
    /// policy) — a duplicate `(term, category)` is skipped silently.
    public func addVocabulary(_ records: [VocabularyRecord]) throws {
        try database.write { db in
            for var record in records {
                try record.insert(db)
            }
        }
        // Coarse only: the count is not a payload; no term is ever logged.
        log.event("vocabulary added")
        log.logLength(of: records)
    }

    public func vocabulary(limit: Int) -> [Term] {
        let records = (try? database.read { db in
            try VocabularyRecord
                .order(Column("weight").desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []

        // Coarse only: the COUNT is not a payload; no term/expansion is ever logged.
        log.event("vocabulary fetched")
        log.logLength(of: records)

        return records.map { record in
            Term(
                term: record.term,
                expansion: record.expansion,
                lang: Self.language(record.lang),
                weight: record.weight
            )
        }
    }

    /// Every stored vocabulary row, unfiltered and uncapped — the Settings
    /// vocabulary table's read. Unlike `vocabulary(limit:)`, which swallows a read
    /// failure into `[]` so the dictation pipeline degrades gracefully, this method
    /// `throws`: the management UI must be able to tell a genuine read failure apart
    /// from an empty store.
    public func allVocabulary() throws -> [VocabularyRecord] {
        let records = try database.read { db in
            try VocabularyRecord.order(Column("weight").desc).fetchAll(db)
        }
        // Coarse only: the COUNT is not a payload; no term is ever logged.
        log.event("vocabulary listed")
        log.logLength(of: records)
        return records
    }

    /// Deletes the row with the given stable id; a missing id is a no-op.
    public func removeVocabulary(id: Int64) throws {
        try database.write { db in
            // filter+deleteAll needs only TableRecord. GRDB's deleteOne(_:id:) would
            // require a `VocabularyRecord: Identifiable` conformance we deliberately
            // don't add; this targets the unique id column, deleting at most one row.
            _ = try VocabularyRecord.filter(Column("id") == id).deleteAll(db)
        }
        // Coarse only: no id or row payload is logged.
        log.event("vocabulary removed")
    }

    private static func language(_ raw: String) -> Language {
        switch raw {
        case "ru": return .ru
        case "en": return .en
        default: return .auto
        }
    }
}
