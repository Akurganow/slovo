import Foundation
import Testing
import GRDB

import SlovoCore

// Create-or-get (missing DB ⇒ migrator creates it empty) and idempotent re-run.
//
// Contract under test lives in `Sources/SlovoCore/Storage/Database.swift` +
// `Migrations.swift`.
//
// ON-DISK temp DB only (in-memory masks create-or-get). SEED-LEAK RULE:
// synthetic public anchors only.
@Suite("Migrations")
struct MigrationsTests {

    /// Opening at a NON-EXISTENT path creates the DB and an empty
    /// `vocabulary`; `vocabulary()` returns `[]` without crashing.
    /// Stated sensitivity: branch on file-exists and skip the migrator when the
    /// file is missing → the table doesn't exist → the query crashes/errors → RED.
    @Test
    func openCreatesEmptyDatabaseWhenMissing() throws {
        let path = TempDatabase.freshPath()
        defer { TempDatabase.remove(at: path) }
        #expect(!FileManager.default.fileExists(atPath: path), "precondition: the DB file must not exist yet")

        let pool = try PersonalizationDatabase.open(at: path)
        #expect(FileManager.default.fileExists(atPath: path), "open must create the DB file")

        let tableExists = try pool.read { db in try db.tableExists("vocabulary") }
        #expect(tableExists, "the migrator must create the vocabulary table on a fresh DB")

        let count = try pool.read { db in try VocabularyRecord.fetchCount(db) }
        #expect(count == 0, "a freshly created vocabulary is empty — a valid state")
    }

    /// Migrating an already-up-to-date DB is a no-op (idempotent).
    /// Stated sensitivity: re-run a migration body unconditionally (e.g. a raw
    /// `CREATE TABLE` without `IF NOT EXISTS`/migrator tracking) → the second
    /// migrate throws "table exists" → RED.
    @Test
    func migratingTwiceIsIdempotent() throws {
        let (pool, _, teardown) = try TempDatabase.freshPool()
        defer { teardown() }

        try PersonalizationMigrations.migrator.migrate(pool)
        // Second migrate must NOT throw and must leave the schema unchanged.
        #expect(throws: Never.self) {
            try PersonalizationMigrations.migrator.migrate(pool)
        }
        let applied = try pool.read { db in try PersonalizationMigrations.migrator.appliedMigrations(db) }
        #expect(applied.contains("v1.createSchema"), "the v1 migration must be recorded once")
    }
}
