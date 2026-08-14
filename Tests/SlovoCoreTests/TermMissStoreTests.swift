import Foundation
import GRDB
import Testing

import SlovoCore

// term_misses persistence: insert + same-transaction prune, retention
// boundary, fetch shape. ON-DISK temp DB via the existing TempDatabase
// helper (see VocabularyStoreTests). Spec section "Storage".
@Suite("Term miss store")
struct TermMissStoreTests {
    private static func openStore() throws -> (pool: DatabasePool, teardown: () -> Void) {
        let path = TempDatabase.freshPath()
        let pool = try PersonalizationDatabase.open(at: path)
        return (pool, { TempDatabase.remove(at: path) })
    }

    /// Insert/fetch roundtrip, grouped by key.
    /// Stated sensitivity: fetch WHERE term_key = '' → empty dictionary → RED.
    @Test
    func recordedMissesRoundTrip() async throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }
        let store = GRDBTermMissStore(database: pool)

        await store.recordMisses(["github", "github", "wispr flow"])

        let dates = try store.missDatesByKey()
        #expect(dates["github"]?.count == 2)
        #expect(dates["wispr flow"]?.count == 1)
    }

    /// The 90-day prune runs in the SAME write transaction as the insert:
    /// a 91-day-old row is DELETED by the next record, an 89-day-old survives.
    ///
    /// The expired row's absence is asserted with direct SQL, not through
    /// `missDatesByKey()`: that read filters the retention window itself, so it
    /// reports the row gone whether or not the DELETE ever ran — which would
    /// leave the prune entirely unpinned.
    /// Stated sensitivity: remove the DELETE from `recordMisses` → the
    /// 91-day row is still in the table → RED.
    @Test
    func pruneRemovesOnlyExpiredRows() async throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }
        try await pool.write { db in
            try db.execute(
                sql: "INSERT INTO term_misses (term_key, created_at) VALUES ('old', datetime('now', '-91 days')), ('recent', datetime('now', '-89 days'))"
            )
        }
        let store = GRDBTermMissStore(database: pool)

        await store.recordMisses(["fresh"])

        let storedOldRows = try await pool.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM term_misses WHERE term_key = 'old'") ?? -1
        }
        #expect(storedOldRows == 0)
        let dates = try store.missDatesByKey()
        #expect(dates["recent"]?.count == 1)
        #expect(dates["fresh"]?.count == 1)
    }

    /// An empty batch writes nothing and does not touch the database — proven
    /// by an expired row that the prune WOULD have deleted still sitting in the
    /// table. Read with SQL rather than `missDatesByKey`, which filters the
    /// retention window on read and so cannot see the row either way.
    /// Stated sensitivity: drop the isEmpty guard and always open the write →
    /// the prune runs and deletes the row → RED.
    @Test
    func emptyBatchIsANoOp() async throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }
        try await pool.write { db in
            try db.execute(sql: "INSERT INTO term_misses (term_key, created_at) VALUES ('old', datetime('now', '-91 days'))")
        }
        let store = GRDBTermMissStore(database: pool)

        await store.recordMisses([])

        let storedOldRows = try await pool.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM term_misses WHERE term_key = 'old'") ?? -1
        }
        #expect(storedOldRows == 1)
    }

    /// Retention is enforced on READ too, not only by the write-time prune: a
    /// 91-day-old row is invisible to the ranker even when no dictation ever
    /// records again (the prune only runs on a write, so a user who stops
    /// producing misses would otherwise rank on arbitrarily stale rows).
    /// Stated sensitivity: drop the `WHERE created_at >= …` from
    /// `missDatesByKey` → the stale row comes back → RED.
    @Test
    func staleRowsAreInvisibleWithoutAPrune() throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }
        try pool.write { db in
            try db.execute(
                sql: "INSERT INTO term_misses (term_key, created_at) VALUES ('stale', datetime('now', '-91 days')), ('fresh', datetime('now', '-1 days'))"
            )
        }

        // No recordMisses call: nothing triggers the write-time prune.
        let dates = try GRDBTermMissStore(database: pool).missDatesByKey()

        #expect(dates["stale"] == nil)
        #expect(dates["fresh"]?.count == 1)
    }

    /// A write failure is swallowed into a coarse log event — the pipeline
    /// contract (`TermMissRecording` is non-throwing).
    /// Stated sensitivity: let `recordMisses` trap on error instead of
    /// logging → this test crashes → RED.
    @Test
    func writeFailureIsCoarselyLoggedNotThrown() async throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }
        try await pool.write { db in try db.execute(sql: "DROP TABLE term_misses") }
        var events: [String] = []
        let log = RedactionSafeLog(subsystem: "test", category: "storage") { events.append($0) }
        let store = GRDBTermMissStore(database: pool, log: log)

        await store.recordMisses(["github"])

        #expect(events.contains { $0.contains("term miss write failed") })
        #expect(events.allSatisfy { !$0.contains("github") })
    }
}
