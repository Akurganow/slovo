import Foundation
import Testing
import GRDB

import SlovoCore

// Dedup on (term, category), top-N by weight, and seed idempotency (corrections
// inert).
//
// Contract under test (implementer builds `Sources/SlovoCore/Storage/`;
// CURRENTLY the `_RedScaffold_Storage.swift` stub — UNIQUE(term), unordered
// source, no-INSERT-OR-IGNORE seed — so these go RED).
//
// ON-DISK temp DB. Every term is a synthetic neutral public anchor.
@Suite("Vocabulary store")
struct VocabularyStoreTests {

    private static func openStore() throws -> (pool: DatabasePool, teardown: () -> Void) {
        let path = TempDatabase.freshPath()
        let pool = try PersonalizationDatabase.open(at: path)
        return (pool, { TempDatabase.remove(at: path) })
    }

    /// The same `term` under two DIFFERENT categories both survive; the same
    /// `term` + same `category` dedups to one.
    /// Stated sensitivity: declare `UNIQUE(term)` (drop `category`) → the
    /// two-category case collapses to 1 → RED. (The scaffold uses
    /// `UNIQUE(term)` → RED now.)
    @Test
    func dedupIsPerTermAndCategory() throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }

        try SeedImport.importRows([
            VocabularyRecord(term: "GitHub", category: "tool"),
            VocabularyRecord(term: "GitHub", category: "org"),   // same term, different category → BOTH survive
        ], into: pool)
        let twoCategories = try pool.read { db in try VocabularyRecord.fetchCount(db) }
        #expect(twoCategories == 2, "the same term in two categories must both survive (UNIQUE(term, category)); got \(twoCategories)")

        // Same (term, category) inserted again must dedup to one (no extra row).
        try SeedImport.importRows([VocabularyRecord(term: "GitHub", category: "tool")], into: pool)
        let afterDuplicate = try pool.read { db in
            try VocabularyRecord.filter(Column("term") == "GitHub" && Column("category") == "tool").fetchCount(db)
        }
        #expect(afterDuplicate == 1, "the same (term, category) must dedup to a single row; got \(afterDuplicate)")
    }

    /// `vocabulary(limit:)` returns the highest-weight N terms in descending
    /// order. Expected `[w9, w7, w5]` from the FIXTURE weights, not the source.
    /// Stated sensitivity: drop/reverse the `.order(weight.desc)` → wrong set/order
    /// → RED. (The scaffold is unordered → RED now.)
    @Test
    func vocabularyReturnsTopNByWeightInOrder() throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }

        // Insert in a deliberately non-weight order so insertion-order ≠ weight order.
        try SeedImport.importRows([
            VocabularyRecord(term: "w5", category: "tech", weight: 5),
            VocabularyRecord(term: "w3", category: "tech", weight: 3),
            VocabularyRecord(term: "w9", category: "tech", weight: 9),
            VocabularyRecord(term: "w1", category: "tech", weight: 1),
            VocabularyRecord(term: "w7", category: "tech", weight: 7),
        ], into: pool)

        let top = GRDBPersonalizationSource(database: pool).vocabulary(limit: 3).map(\.term)
        #expect(top == ["w9", "w7", "w5"],
                "vocabulary(limit: 3) must return the top-3 by weight in descending order [w9, w7, w5]; got \(top)")
    }

    /// Applying a SYNTHETIC seed twice leaves `vocabulary` un-duplicated and
    /// `corrections` empty throughout (the real seed file is NEVER read in CI).
    /// Stated sensitivity: import without `INSERT OR IGNORE` → the re-apply either
    /// duplicates (no unique key) or throws SQLite-19 (unique key) → RED; write to
    /// `corrections` during import → count > 0 → RED. GREEN on the
    /// correct-IGNORE scaffold; the no-`.ignore` RED is proven OUT-OF-BAND (it
    /// can't coexist in-tree with the clean UNIQUE(term) count-mismatch — a
    /// plain INSERT throws on conflict rather than yielding a clean count).
    @Test
    func seedReapplyIsIdempotentAndLeavesCorrectionsUntouched() throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }

        // SYNTHETIC seed — public anchors only, never the real data/seed*.sql.
        let seed = [
            VocabularyRecord(term: "ExampleCorp", category: "org", weight: 9),
            VocabularyRecord(term: "kubectl", category: "tech", weight: 5),
            VocabularyRecord(term: "GitHub", category: "tool", weight: 7),
        ]

        try SeedImport.importRows(seed, into: pool)
        let afterFirst = try pool.read { db in try VocabularyRecord.fetchCount(db) }
        #expect(afterFirst == 3, "first seed apply must insert 3 rows; got \(afterFirst)")

        try SeedImport.importRows(seed, into: pool)  // re-apply
        let afterSecond = try pool.read { db in try VocabularyRecord.fetchCount(db) }
        #expect(afterSecond == 3, "re-applying the seed must NOT duplicate rows (INSERT OR IGNORE); got \(afterSecond)")

        let corrections = try pool.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM corrections") ?? -1 }
        #expect(corrections == 0, "the seed import must never write to corrections (inert in v1); got \(corrections)")
    }
}
