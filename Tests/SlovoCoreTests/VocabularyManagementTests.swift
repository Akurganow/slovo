import Foundation
import Testing
import GRDB

import SlovoCore

// list-all + remove-by-id on the personalization store, exercised against a fresh
// on-disk pool (the same pattern as VocabularyStoreTests — DatabasePool has no
// in-memory mode). Every term is a synthetic neutral public anchor.
@Suite("Vocabulary management")
struct VocabularyManagementTests {

    private static func openStore() throws -> (source: GRDBPersonalizationSource, teardown: () -> Void) {
        let path = TempDatabase.freshPath()
        let pool = try PersonalizationDatabase.open(at: path, passphrase: TempDatabase.passphrase)
        return (GRDBPersonalizationSource(database: pool), { TempDatabase.remove(at: path) })
    }

    /// list-all returns every stored row, so the Settings table can never silently
    /// hide terms the user added.
    /// Stated sensitivity: add any `.limit(n)` with n < 60 to `allVocabulary()`'s
    /// query → fewer than 60 rows come back → RED. The seed is 60 rows rather than 3
    /// so that a plausible round-number cap (10, 25, 50) reddens too; a 3-row seed
    /// would let every such cap survive.
    @Test
    func allVocabularyReturnsEveryStoredRow() throws {
        let (source, teardown) = try Self.openStore()
        defer { teardown() }

        let seeded = (1...60).map { index in
            VocabularyRecord(term: "term-\(index)", category: "tech", weight: 1)
        }
        try source.addVocabulary(seeded)

        let terms = try source.allVocabulary().map(\.term)
        #expect(terms.count == 60,
                "allVocabulary must return every stored row (60), not a capped subset; got \(terms.count)")
        #expect(Set(terms) == Set(seeded.map(\.term)),
                "allVocabulary must return exactly the stored terms")
        // Every row shares weight 1, so the term tie-break alone decides the order the
        // Settings table renders. Lexicographic, not numeric: "term-10" precedes "term-2".
        // Stated sensitivity: drop `Column("term").asc` from `allVocabulary()`'s ORDER BY
        // → the equal-weight rows come back in an unspecified order, here
        // ["term-9", "term-8", "term-7"] → RED. Which order SQLite picks is a query-plan
        // detail and differs between fixtures, so the pin is on the term order alone.
        #expect(Array(terms.prefix(3)) == ["term-1", "term-10", "term-11"],
                "equal-weight rows must render in term order; got \(Array(terms.prefix(3)))")
    }

    /// remove-by-id deletes exactly the identified row and leaves the rest.
    /// Stated sensitivity: a remove that ignores its id argument (deletes the wrong
    /// row, all rows, or none) → the surviving set is wrong → RED.
    @Test
    func removeVocabularyDeletesOnlyTheIdentifiedRow() throws {
        let (source, teardown) = try Self.openStore()
        defer { teardown() }

        try source.addVocabulary([
            VocabularyRecord(term: "GitHub", category: "tool", weight: 1),
            VocabularyRecord(term: "OAuth", category: "tech", weight: 1),
            VocabularyRecord(term: "PostgreSQL", category: "tech", weight: 1),
        ])

        let stored = try source.allVocabulary()
        let oauthId = try #require(stored.first { $0.term == "OAuth" }?.id)

        try source.removeVocabulary(id: oauthId)

        let survivors = try source.allVocabulary().map(\.term).sorted()
        #expect(survivors == ["GitHub", "PostgreSQL"],
                "remove(id:) must delete only the identified row; got \(survivors)")
    }

    /// Removing an id that is not present is a no-op, not an error.
    /// Stated sensitivity: throw or delete a fallback row when the id is missing →
    /// the count changes or an error is thrown → RED.
    @Test
    func removeVocabularyOfMissingIdIsANoOp() throws {
        let (source, teardown) = try Self.openStore()
        defer { teardown() }

        try source.addVocabulary([VocabularyRecord(term: "GitHub", category: "tool", weight: 1)])
        let before = try source.allVocabulary().count

        try source.removeVocabulary(id: 999_999)

        let after = try source.allVocabulary().count
        #expect(before == after && after == 1, "removing a missing id must not change the store")
    }
}
