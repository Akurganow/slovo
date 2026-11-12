import Foundation
import GRDB
import Testing
@testable import SlovoCore

// A database an older SQLCipher wrote must still open under the linked one. A
// file the new library cannot read is set aside as `.unreadable` and replaced
// by an empty database, so the user's vocabulary vanishes without an error.
// The fixture was opened at a fresh path by `PersonalizationDatabase.open` with
// `fixturePassphrase` under GRDB.swift 7.11.1 and SQLCipher.swift 4.17.0, then
// `fixtureTerms` were inserted in order and the pool was closed. The file is
// kept as written and never regenerated; a later file-format baseline adds its
// own fixture beside it. Its terms are synthetic.
@Suite("Personalization database fixture")
struct PersonalizationDatabaseFixtureTests {
    private static let fixtureName = "personalization-sqlcipher-4.17.0.sqlite"
    private static let fixturePassphrase: @Sendable () throws -> String = { "slovo-fixture-passphrase" }
    private static let fixtureTerms = ["fixture-alpha", "fixture-beta", "фикстура-гамма"]

    /// Stated sensitivity: a linked SQLCipher that cannot read the 4.17.0 file
    /// format → `SQLITE_NOTADB` → set aside and replaced empty → RED; a
    /// migration that fails on, or deletes, rows already on disk → RED through
    /// the thrown error or the terms expectation; the fixture replaced by a
    /// plaintext file, which `open` would encrypt in place → RED on the
    /// precondition. Control: a wrong passphrase in this test → RED.
    @Test
    func databaseWrittenBySQLCipher4_17_0StillOpens() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/" + Self.fixtureName)
        let path = TempDatabase.freshPath()
        defer { TempDatabase.remove(at: path) }
        try FileManager.default.copyItem(atPath: fixture.path, toPath: path)
        #expect(try PersonalizationDatabase.fileState(at: path) == .opaque)

        let pool = try PersonalizationDatabase.open(at: path, passphrase: Self.fixturePassphrase)
        defer { try? pool.close() }
        let terms = try pool.read { db in
            try String.fetchAll(db, sql: "SELECT term FROM vocabulary ORDER BY id")
        }

        #expect(terms == Self.fixtureTerms)
    }
}
