import Foundation
import GRDB
import Testing
@testable import SlovoCore

// A database an older SQLCipher wrote must still open under the linked one. A
// file the new library cannot read is set aside as `.unreadable` and replaced
// by an empty database, so the user's vocabulary vanishes without an error.
// The fixture was written by `PersonalizationDatabase.open` under SQLCipher
// 4.17.0 with `fixturePassphrase`, then migrated and filled with
// `fixtureTerms`. Its terms are synthetic.
@Suite("Personalization database fixture")
struct PersonalizationDatabaseFixtureTests {
    private static let fixtureName = "personalization-sqlcipher-4.17.0.sqlite"
    private static let fixturePassphrase: @Sendable () throws -> String = { "slovo-fixture-passphrase" }
    private static let fixtureTerms = ["fixture-alpha", "fixture-beta", "фикстура-гамма"]

    /// Stated sensitivity: a linked SQLCipher that cannot read the 4.17.0 file
    /// format → `SQLITE_NOTADB` → set aside and replaced empty → RED on both
    /// expectations; a wrong passphrase in this test → RED the same way.
    @Test
    func databaseWrittenBySQLCipher4_17_0StillOpens() throws {
        let fixture = URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(Self.fixtureName)
        let path = TempDatabase.freshPath()
        defer { TempDatabase.remove(at: path) }
        try FileManager.default.copyItem(atPath: fixture.path, toPath: path)

        let pool = try PersonalizationDatabase.open(at: path, passphrase: Self.fixturePassphrase)
        defer { try? pool.close() }
        let terms = try pool.read { db in
            try String.fetchAll(db, sql: "SELECT term FROM vocabulary ORDER BY id")
        }

        #expect(terms == Self.fixtureTerms)
        #expect(!FileManager.default.fileExists(atPath: path + PersonalizationDatabase.unreadableSuffix))
    }
}
