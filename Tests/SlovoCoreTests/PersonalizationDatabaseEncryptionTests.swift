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

    /// Spec test 4c: a leftover `.encrypting` next to an already-ENCRYPTED
    /// database is removed on open — after a crash inside the swap window the
    /// leftover IS the plaintext original (replaceItemAt swaps, then unlinks),
    /// and the .plaintext arm will never run again to clean it.
    /// Stated sensitivity: cleanup living only inside encryptInPlace → the
    /// leftover survives the reopen → RED.
    @Test
    func leftoverTempNextToEncryptedDatabaseIsRemovedOnOpen() throws {
        let path = TempDatabase.freshPath()
        defer { TempDatabase.remove(at: path) }
        let pool = try PersonalizationDatabase.open(at: path, passphrase: Self.passphraseA)
        try pool.close()
        try Data("plaintext orphan".utf8).write(to: URL(fileURLWithPath: path + ".encrypting"))

        let reopened = try PersonalizationDatabase.open(at: path, passphrase: Self.passphraseA)
        defer { try? reopened.close() }
        #expect(!FileManager.default.fileExists(atPath: path + ".encrypting"))
    }

    /// Spec test 5: an encrypted DB this key cannot read (another Mac, board
    /// swap) is silently set aside — KEPT, not deleted — and a fresh empty
    /// encrypted DB takes its place; a second wrong-key round REPLACES the
    /// aside (one generation).
    /// Stated sensitivity: delete-instead-of-rename → `.unreadable` missing →
    /// RED; rethrow-instead-of-set-aside → open throws → RED; reusing the
    /// unreadable file → non-empty vocabulary → RED; drop the pre-delete of
    /// the older aside → the second round's move collides → open throws → RED.
    @Test
    func unreadableEncryptedDatabaseIsSetAsideAndReplacedFresh() throws {
        let path = TempDatabase.freshPath()
        defer { TempDatabase.remove(at: path) }
        let foreign = try PersonalizationDatabase.open(at: path, passphrase: Self.passphraseA)
        try foreign.write { db in
            try db.execute(
                sql: "INSERT INTO vocabulary (term, category, source) VALUES ('foreign-term', 'test', 'import')"
            )
        }
        let seeded = try foreign.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM vocabulary")
        }
        #expect(seeded == 1, "precondition: the foreign database must actually hold a row")
        try foreign.close()

        let pool = try PersonalizationDatabase.open(at: path, passphrase: Self.passphraseB)
        let count = try pool.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM vocabulary")
        }
        #expect(count == 0)
        #expect(FileManager.default.fileExists(atPath: path + ".unreadable"))
        #expect(try Self.header(at: path) != Self.plaintextHeader)
        try pool.close()

        // One generation: the fresh DB is keyed under B, so opening with A is
        // a second wrong-key round — it must replace the aside, not collide.
        let second = try PersonalizationDatabase.open(at: path, passphrase: Self.passphraseA)
        defer { try? second.close() }
        #expect(FileManager.default.fileExists(atPath: path + ".unreadable"))
    }

    /// Spec test 5b: a file that is neither plaintext nor a readable database
    /// under the key (short garbage) takes the same set-aside path —
    /// empirically pinning that such files surface as SQLITE_NOTADB. If this
    /// test reds with a DIFFERENT error code, STOP and report to the lead:
    /// the catch is never widened silently.
    /// Stated sensitivity: rethrow-instead-of-set-aside → open throws → RED;
    /// a sniff that calls short garbage "plaintext" → the migration path
    /// fails on it → RED.
    @Test
    func corruptedFileIsSetAsideAndReplacedFresh() throws {
        let path = TempDatabase.freshPath()
        defer { TempDatabase.remove(at: path) }
        try Data("garbage".utf8).write(to: URL(fileURLWithPath: path))

        let pool = try PersonalizationDatabase.open(at: path, passphrase: Self.passphraseA)
        defer { try? pool.close() }
        let count = try pool.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM vocabulary")
        }
        #expect(count == 0)
        #expect(FileManager.default.fileExists(atPath: path + ".unreadable"))
    }

    /// Spec test 5c: the failed wrong-key open folds WAL pages into the main
    /// file before deleting the sidecars (measured), so the preserved
    /// `.unreadable` file is complete on its own — the "keep the bytes"
    /// promise depends on it.
    /// Stated sensitivity: a SQLite that deletes a foreign WAL without
    /// checkpointing it → the WAL-only row vanishes from the recovered file
    /// → RED.
    @Test
    func setAsideKeepsWalResidentRowsRecoverable() throws {
        let live = TempDatabase.freshPath()
        let copy = TempDatabase.freshPath()
        let recovered = TempDatabase.freshPath()
        defer {
            TempDatabase.remove(at: live)
            TempDatabase.remove(at: copy)
            TempDatabase.remove(at: recovered)
        }
        let manager = FileManager.default

        let pool = try PersonalizationDatabase.open(at: live, passphrase: Self.passphraseA)
        try pool.write { db in
            try db.execute(
                sql: "INSERT INTO vocabulary (term, category, source) VALUES ('wal-only-term', 'test', 'import')"
            )
        }
        // Copied while the pool is still OPEN, so the row is WAL-resident —
        // the state a database copied from a running Mac actually arrives in.
        for suffix in ["", "-wal", "-shm"] where manager.fileExists(atPath: live + suffix) {
            try manager.copyItem(atPath: live + suffix, toPath: copy + suffix)
        }
        let walSize = try #require(
            manager.attributesOfItem(atPath: copy + "-wal")[.size] as? Int,
            "the copy must carry a wal file"
        )
        // Vacuity guard: a wal holding nothing but its 32-byte header would
        // mean the row was already checkpointed and this test proves nothing.
        try #require(walSize > 32, "the row must still be wal-resident")
        try pool.close()

        let fresh = try PersonalizationDatabase.open(at: copy, passphrase: Self.passphraseB)
        defer { try? fresh.close() }
        try #require(manager.fileExists(atPath: copy + ".unreadable"))
        // The single-file-move contract: the set-aside carries the main file
        // only. (The live `-wal`/`-shm` beside it now belong to the fresh
        // replacement pool, so they say nothing about the foreign database —
        // test 5d pins that half.)
        #expect(!manager.fileExists(atPath: copy + ".unreadable-wal"))
        #expect(!manager.fileExists(atPath: copy + ".unreadable-shm"))

        // The documented manual-recovery path: take the set-aside bytes
        // elsewhere and open them with the key that made them.
        try manager.moveItem(atPath: copy + ".unreadable", toPath: recovered)
        let reopened = try PersonalizationDatabase.open(at: recovered, passphrase: Self.passphraseA)
        defer { try? reopened.close() }
        let terms = try reopened.read { db in
            try String.fetchAll(db, sql: "SELECT term FROM vocabulary")
        }
        #expect(terms == ["wal-only-term"])
    }

    /// Spec test 6: if re-encryption cannot complete, THIS session serves the
    /// plaintext file unchanged and the next launch retries. The failure is
    /// forced with an immutable (uchg) file at the temp path — file-scoped on
    /// purpose: a read-only parent directory would also block the fallback's
    /// own WAL sidecars, breaking the very path under test. If this test is
    /// ever killed mid-run, the leftover survives `rm -rf` until
    /// `chflags nouchg` clears it (the defer handles normal completion).
    /// Stated sensitivity: rethrow-instead-of-fallback → open throws → RED;
    /// fallback to a FRESH db instead of the existing plaintext one → row
    /// assertion RED; a state machine that never retries → second-open header
    /// assertion RED.
    @Test
    func failedMigrationFallsBackToPlaintextForThisSession() throws {
        let path = TempDatabase.freshPath()
        let temporaryPath = path + ".encrypting"
        defer {
            _ = chflags(temporaryPath, 0)
            TempDatabase.remove(at: path)
        }
        try Self.makePlaintextDatabase(at: path, terms: ["epsilon-term"])
        try Data().write(to: URL(fileURLWithPath: temporaryPath))
        try #require(chflags(temporaryPath, UInt32(UF_IMMUTABLE)) == 0)

        let pool = try PersonalizationDatabase.open(at: path, passphrase: Self.passphraseA)
        let terms = try pool.read { db in
            try String.fetchAll(db, sql: "SELECT term FROM vocabulary")
        }
        #expect(terms == ["epsilon-term"])
        #expect(try Self.header(at: path) == Self.plaintextHeader)
        try pool.close()

        // Next-launch retry: with the blocker gone the migration completes.
        try #require(chflags(temporaryPath, 0) == 0)
        let retried = try PersonalizationDatabase.open(at: path, passphrase: Self.passphraseA)
        defer { try? retried.close() }
        #expect(try Self.header(at: path) != Self.plaintextHeader)
    }

    /// Spec test 5d: characterization tripwire — a FAILED keyed open deletes
    /// foreign `-wal`/`-shm` (after folding their pages into the main file;
    /// see 5c). The set-aside's single-file-move contract depends on this: if
    /// a future SQLite stops cleaning them, stale foreign sidecars would sit
    /// next to the fresh replacement database, and this test reddens first.
    /// Stated sensitivity: platform characterization (like 4b) — no slovo
    /// mutation reddens it; a SQLite/SQLCipher behavior change does.
    @Test
    func failedKeyedOpenLeavesNoForeignSidecars() throws {
        let path = TempDatabase.freshPath()
        defer { TempDatabase.remove(at: path) }
        let manager = FileManager.default

        let foreign = try PersonalizationDatabase.open(at: path, passphrase: Self.passphraseA)
        try foreign.close()
        try Data("wal remnant".utf8).write(to: URL(fileURLWithPath: path + "-wal"))
        try Data("shm remnant".utf8).write(to: URL(fileURLWithPath: path + "-shm"))

        #expect(throws: (any Error).self) {
            let wrongKey = try DatabasePool(
                path: path,
                configuration: PersonalizationDatabase.keyedConfiguration(passphrase: Self.passphraseB)
            )
            try wrongKey.close()
        }

        #expect(!manager.fileExists(atPath: path + "-wal"))
        #expect(!manager.fileExists(atPath: path + "-shm"))
        #expect(manager.fileExists(atPath: path))
    }

    /// A non-wrong-key open failure (here: permissions) must PROPAGATE — never
    /// be answered by setting a readable database aside and starting empty.
    /// Stated sensitivity: widening the .opaque catch beyond SQLITE_NOTADB →
    /// the aside appears and open succeeds → RED on both assertions.
    @Test
    func nonWrongKeyOpenFailurePropagatesInsteadOfSettingAside() throws {
        let path = TempDatabase.freshPath()
        defer {
            _ = chmod(path, 0o600)
            TempDatabase.remove(at: path)
        }
        let pool = try PersonalizationDatabase.open(at: path, passphrase: Self.passphraseA)
        try pool.close()
        try #require(chmod(path, 0) == 0)

        #expect(throws: (any Error).self) {
            _ = try PersonalizationDatabase.open(at: path, passphrase: Self.passphraseA)
        }
        #expect(!FileManager.default.fileExists(atPath: path + ".unreadable"),
                "a permission error must not be treated as a wrong key")
    }

    /// A failing passphrase provider must fail the open outright — never fall
    /// through to an unkeyed or empty-key database.
    /// Stated sensitivity: swallowing the provider's error inside
    /// `keyedConfiguration` (e.g. `try? passphrase() ?? ""`) → open succeeds
    /// and a database file appears → RED on both assertions.
    @Test
    func throwingPassphraseProviderFailsTheOpenWithoutCreatingAFile() throws {
        let path = TempDatabase.freshPath()
        defer { TempDatabase.remove(at: path) }

        #expect(throws: PersonalizationDatabasePassphrase.ReadError.self) {
            _ = try PersonalizationDatabase.open(at: path, passphrase: {
                throw PersonalizationDatabasePassphrase.ReadError.uuidMissing
            })
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        #expect((attributes[.size] as? Int) == 0,
                "a failed derivation must leave no database — at most the empty file SQLite pre-created")
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
