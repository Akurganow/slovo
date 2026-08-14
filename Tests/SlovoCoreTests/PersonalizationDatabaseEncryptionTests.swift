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
}
