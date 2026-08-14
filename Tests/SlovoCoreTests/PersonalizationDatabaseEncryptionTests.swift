import Foundation
import GRDB
import Testing

// @testable only for the internal `derive(from:)` (distinct per-machine test
// passphrases) and, from Task 4 on, the internal `fileState(at:)` oracle.
@testable import SlovoCore

// On-disk state machine of PersonalizationDatabase.open: fresh-create,
// plaintext migration, crash recovery, wrong-key set-aside, failure fallback.
// Spec: docs/superpowers/specs/2026-08-14-personalization-db-encryption-design.md (v2).
@Suite("Personalization database encryption")
struct PersonalizationDatabaseEncryptionTests {
    private static let plaintextHeader = Data("SQLite format 3\u{0}".utf8)
    private static let passphraseA: @Sendable () throws -> String =
        { PersonalizationDatabasePassphrase.derive(from: "test-machine-A") }
    private static let passphraseB: @Sendable () throws -> String =
        { PersonalizationDatabasePassphrase.derive(from: "test-machine-B") }

    /// Reads the file's 16-byte SQLite header, REQUIRING all 16 bytes — a
    /// short read (empty/truncated file) must fail the test, not slip past an
    /// inequality check as "encrypted".
    private static func header(at path: String) throws -> Data {
        let handle = try #require(FileHandle(forReadingAtPath: path))
        defer { try? handle.close() }
        let header = try #require(try handle.read(upToCount: 16))
        try #require(header.count == 16, "file shorter than one SQLite header")
        return header
    }

    /// Spec test 1: "no file → create encrypted from the start".
    /// Stated sensitivity: dropping the passphrase hookup (keyless creation)
    /// leaves the plaintext header → RED; a codec-less GRDB build → RED (the
    /// file would be plaintext); writing garbage instead of a database → the
    /// keyed reopen read-back → RED.
    @Test
    func freshDatabaseIsEncryptedOnDisk() throws {
        let path = TempDatabase.freshPath()
        defer { TempDatabase.remove(at: path) }

        let pool = try PersonalizationDatabase.open(at: path, passphrase: Self.passphraseA)
        try pool.write { db in
            try db.execute(
                sql: "INSERT INTO vocabulary (term, category, source) VALUES ('fresh-term', 'test', 'import')"
            )
        }
        try pool.close()

        #expect(try Self.header(at: path) != Self.plaintextHeader)

        let reopened = try PersonalizationDatabase.open(at: path, passphrase: Self.passphraseA)
        defer { try? reopened.close() }
        let terms = try reopened.read { db in
            try String.fetchAll(db, sql: "SELECT term FROM vocabulary")
        }
        #expect(terms == ["fresh-term"])
    }

    /// Fabricates the pre-encryption on-disk state: a keyless (plaintext)
    /// pool with the real production schema and the given vocabulary terms.
    private static func makePlaintextDatabase(at path: String, terms: [String]) throws {
        let pool = try DatabasePool(path: path)
        try PersonalizationMigrations.migrator.migrate(pool)
        try pool.write { db in
            for term in terms {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO vocabulary (term, category, source)
                        VALUES (?, 'test', 'import')
                        """,
                    arguments: [term]
                )
            }
        }
        try pool.close()
    }

    /// Spec test 2: plaintext → re-encrypt in place; data and the
    /// UNIQUE(term, category) dedup behavior survive; no temp remnants.
    /// Stated sensitivity: fresh-create instead of sqlcipher_export (data
    /// loss) → row assertions RED; skipping encryption → header RED.
    @Test
    func plaintextDatabaseMigratesWithDataPreserved() throws {
        let path = TempDatabase.freshPath()
        defer { TempDatabase.remove(at: path) }
        try Self.makePlaintextDatabase(at: path, terms: ["alpha-term", "beta-term"])

        let pool = try PersonalizationDatabase.open(at: path, passphrase: Self.passphraseA)
        defer { try? pool.close() }

        let terms = try pool.read { db in
            try String.fetchAll(db, sql: "SELECT term FROM vocabulary ORDER BY term")
        }
        #expect(terms == ["alpha-term", "beta-term"])

        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO vocabulary (term, category, source)
                    VALUES ('alpha-term', 'test', 'import')
                    """
            )
        }
        let count = try pool.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM vocabulary")
        }
        #expect(count == 2)

        #expect(try Self.header(at: path) != Self.plaintextHeader)
        #expect(!FileManager.default.fileExists(atPath: path + ".encrypting"))
    }

    /// Spec test 3: relaunch after migration — the second open must classify
    /// the file as opaque and just open it.
    /// Stated sensitivity: a sniff that misreads an encrypted file as
    /// plaintext re-runs the migration path, which fails on it → RED.
    @Test
    func reopeningAfterMigrationWorks() throws {
        let path = TempDatabase.freshPath()
        defer { TempDatabase.remove(at: path) }
        try Self.makePlaintextDatabase(at: path, terms: ["gamma-two-term"])

        let first = try PersonalizationDatabase.open(at: path, passphrase: Self.passphraseA)
        try first.close()

        let second = try PersonalizationDatabase.open(at: path, passphrase: Self.passphraseA)
        defer { try? second.close() }
        let terms = try second.read { db in
            try String.fetchAll(db, sql: "SELECT term FROM vocabulary")
        }
        #expect(terms == ["gamma-two-term"])
    }

    /// Spec test 4: crash BEFORE the swap leaves plaintext + a stale temp;
    /// the next open deletes the temp and completes the migration.
    /// Stated sensitivity: remove the leftover-temp cleanup → ATTACH meets
    /// the garbage file and fails → DB stays plaintext → header RED.
    @Test
    func crashedMigrationLeftoverIsRecovered() throws {
        let path = TempDatabase.freshPath()
        defer { TempDatabase.remove(at: path) }
        try Self.makePlaintextDatabase(at: path, terms: ["delta-term"])
        try Data("not a database, crashed mid-copy".utf8)
            .write(to: URL(fileURLWithPath: path + ".encrypting"))

        let pool = try PersonalizationDatabase.open(at: path, passphrase: Self.passphraseA)
        defer { try? pool.close() }
        let terms = try pool.read { db in
            try String.fetchAll(db, sql: "SELECT term FROM vocabulary")
        }
        #expect(terms == ["delta-term"])
        #expect(try Self.header(at: path) != Self.plaintextHeader)
        #expect(!FileManager.default.fileExists(atPath: path + ".encrypting"))
    }

    /// Spec test 4b: END-STATE invariant — no plaintext sidecars survive the
    /// migration. SQLite itself deletes them at the plaintext connection's
    /// clean close (measured; the migration carries no removal code) — this
    /// test is the tripwire that forces a removal mechanism back in if that
    /// behavior ever changes (e.g. a persistent-WAL build).
    /// Stated sensitivity: any migration failure → RED (control: forcing
    /// `encryptInPlace` to throw reddens it); SQLite persisting the WAL past
    /// close → the sidecar-absence assertions → RED.
    @Test
    func migrationRemovesPlaintextSidecars() throws {
        let path = TempDatabase.freshPath()
        defer { TempDatabase.remove(at: path) }
        try Self.makePlaintextDatabase(at: path, terms: ["gamma-term"])
        try Data("plaintext wal remnant".utf8).write(to: URL(fileURLWithPath: path + "-wal"))
        try Data("plaintext shm remnant".utf8).write(to: URL(fileURLWithPath: path + "-shm"))

        try PlaintextDatabaseMigration.encryptInPlace(at: path, passphrase: Self.passphraseA)

        #expect(try Self.header(at: path) != Self.plaintextHeader)
        #expect(!FileManager.default.fileExists(atPath: path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: path + "-shm"))
    }

    /// Spec test 8: the classification is total — every possible on-disk
    /// state maps to a defined case. (`fileState` is internal; this test is
    /// its consumer.)
    /// Stated sensitivity: classify empty/short files as plaintext, or drop
    /// the fileExists guard (missing ≠ unreadable) → RED.
    @Test
    func fileStateClassificationIsTotal() throws {
        let path = TempDatabase.freshPath()
        defer { TempDatabase.remove(at: path) }
        #expect(PersonalizationDatabase.fileState(at: path) == .missing)

        try Self.plaintextHeader.write(to: URL(fileURLWithPath: path))
        #expect(PersonalizationDatabase.fileState(at: path) == .plaintext)

        try Data().write(to: URL(fileURLWithPath: path))
        #expect(PersonalizationDatabase.fileState(at: path) == .opaque)

        try Data("garbage".utf8).write(to: URL(fileURLWithPath: path))
        #expect(PersonalizationDatabase.fileState(at: path) == .opaque)
    }
}
