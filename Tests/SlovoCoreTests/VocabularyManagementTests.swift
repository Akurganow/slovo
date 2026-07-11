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
        let pool = try PersonalizationDatabase.open(at: path)
        return (GRDBPersonalizationSource(database: pool), { TempDatabase.remove(at: path) })
    }

    /// list-all returns every stored row (not the weight-capped top-N that
    /// `vocabulary(limit:)` returns).
    /// Stated sensitivity: route `allVocabulary()` through the capped
    /// `vocabulary(limit:)` path, or apply any LIMIT, → fewer than all rows come
    /// back → RED. The seed is 60 rows — more than the app's largest cap
    /// (`vocabularyLimit` = 50) and any plausible LIMIT — so even a mutation that
    /// routes through `vocabulary(limit: 50)` visibly drops rows and reddens; a
    /// 3-row seed would let any cap ≥ 3 survive.
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
