import Foundation
import GRDB

/// The GRDB-backed `PersonalizationSource` (spec §18.2, §18.4). The only place
/// that reads the vocabulary table.
///
/// SECURITY (AC-7): a DB-row value (a term, expansion, …) must NEVER reach the
/// log. Only coarse counts cross into `RedactionSafeLog` — never a row payload.
public struct GRDBPersonalizationSource: PersonalizationSource {
    private let database: DatabasePool
    private let log: RedactionSafeLog

    public init(
        database: DatabasePool,
        log: RedactionSafeLog = RedactionSafeLog(subsystem: "loqui", category: "storage")
    ) {
        self.database = database
        self.log = log
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

    private static func language(_ raw: String) -> Language {
        switch raw {
        case "ru": return .ru
        case "en": return .en
        default: return .auto
        }
    }
}
