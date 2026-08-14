import Foundation
import GRDB

/// The GRDB adapter behind `TermMissRecording`: inserts one dictation's miss
/// events and prunes expired rows in the same write transaction, and hands
/// the per-key timestamps to the bias ranking.
///
/// SECURITY: a term key is user-authored vocabulary content and must NEVER
/// reach the log — only coarse counts cross into `RedactionSafeLog`.
///
/// A `term_key` is a folded vocabulary surface (NFC + lowercase + whitespace
/// runs collapsed, which subsumes trimming), not a vocabulary row id.
public struct GRDBTermMissStore: TermMissRecording {
    /// With the ranker's 14-day half-life a 90-day-old event weighs under
    /// 1.2% — noise. The prune shares the insert's transaction so it cannot
    /// outlive a failed write.
    public static let retentionDays = 90

    private let database: DatabasePool
    private let log: RedactionSafeLog

    public init(
        database: DatabasePool,
        log: RedactionSafeLog = RedactionSafeLog(subsystem: "slovo", category: "storage")
    ) {
        self.database = database
        self.log = log
    }

    public func recordMisses(_ termKeys: [String]) async {
        guard !termKeys.isEmpty else { return }
        do {
            try await database.write { db in
                for key in termKeys {
                    try db.execute(sql: "INSERT INTO term_misses (term_key) VALUES (?)", arguments: [key])
                }
                try db.execute(
                    sql: "DELETE FROM term_misses WHERE created_at < datetime('now', ?)",
                    arguments: ["-\(Self.retentionDays) days"]
                )
            }
            // Coarse only: the count is not a payload; no key is ever logged.
            log.event("term misses recorded")
            log.logLength(of: termKeys)
        } catch {
            log.event("term miss write failed")
        }
    }

    /// Every retained event's timestamp, grouped by folded key, for the ranker.
    ///
    /// The window is applied on READ as well as on write: pruning only happens
    /// when a dictation records something, so a user who stops producing misses
    /// would otherwise keep ranking on — and counting — arbitrarily stale rows.
    public func missDatesByKey() throws -> [String: [Date]] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT term_key, created_at FROM term_misses
                    WHERE created_at >= datetime('now', ?)
                    """,
                arguments: ["-\(Self.retentionDays) days"]
            )
            var datesByKey: [String: [Date]] = [:]
            for row in rows {
                guard let date = row["created_at"] as Date? else { continue }
                datesByKey[row["term_key"] as String, default: []].append(date)
            }
            return datesByKey
        }
    }
}
