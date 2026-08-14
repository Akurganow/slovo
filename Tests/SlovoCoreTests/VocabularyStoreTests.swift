import Foundation
import Testing
import GRDB

import SlovoCore

// Dedup on (term, category), full ordering by weight, and seed idempotency
// (corrections inert).
//
// Contract under test lives in `Sources/SlovoCore/Storage/`.
//
// ON-DISK temp DB. Every term is a synthetic neutral public anchor.
@Suite("Vocabulary store")
struct VocabularyStoreTests {

    private static func openStore() throws -> (pool: DatabasePool, teardown: () -> Void) {
        let path = TempDatabase.freshPath()
        let pool = try PersonalizationDatabase.open(at: path, passphrase: TempDatabase.passphrase)
        return (pool, { TempDatabase.remove(at: path) })
    }

    /// The same `term` under two DIFFERENT categories both survive; the same
    /// `term` + same `category` dedups to one.
    /// Stated sensitivity: declare `UNIQUE(term)` (drop `category`) → the
    /// two-category case collapses to 1 → RED.
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

    /// `vocabulary()` returns EVERY stored term in descending weight order — the read
    /// is uncapped, and its consumers (the cleanup prompt, the ASR bias head) budget
    /// it themselves. Five distinct-weight anchors pin the ordering; 60 weight-0
    /// fillers sit below them so the fixture outgrows every plausible cap.
    /// Stated sensitivity: drop/reverse the `.order(weight.desc)` → the anchor head
    /// stops being [w9, w7, w5, w3, w1] → RED. Reintroduce `.limit(50)` → 50 rows
    /// instead of 65, and the tail is filler-45 rather than filler-60 → RED; `.limit(10)`
    /// and `.limit(25)` redden the same two expectations. A 5-row fixture (the version
    /// this replaced) let every one of those caps pass. Dropping `Column("term").asc`
    /// also reddens the tail here — the weight-0 group comes back reversed, ending at
    /// filler-01 — which is the unspecified tie order this fixture happens to expose.
    @Test
    func vocabularyReturnsEveryTermByWeightInOrder() throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }

        // Insert in a deliberately non-weight order so insertion-order ≠ weight order.
        let anchors = [
            VocabularyRecord(term: "w5", category: "tech", weight: 5),
            VocabularyRecord(term: "w3", category: "tech", weight: 3),
            VocabularyRecord(term: "w9", category: "tech", weight: 9),
            VocabularyRecord(term: "w1", category: "tech", weight: 1),
            VocabularyRecord(term: "w7", category: "tech", weight: 7),
        ]
        // Zero-padded so term order and numeric order coincide; weight 0 keeps every
        // filler below the anchors.
        let fillers = (1...60).map { index in
            VocabularyRecord(term: String(format: "filler-%02d", index), category: "tech", weight: 0)
        }
        try SeedImport.importRows(anchors + fillers, into: pool)

        let terms = GRDBPersonalizationSource(database: pool).vocabulary().map(\.term)
        #expect(terms.count == 65, "all 65 stored rows must come back uncapped; got \(terms.count)")
        #expect(Array(terms.prefix(5)) == ["w9", "w7", "w5", "w3", "w1"],
                "the weighted anchors must lead in descending weight order; got \(Array(terms.prefix(5)))")
        #expect(terms.last == "filler-60",
                "the lowest-weight tail must survive the read; got \(String(describing: terms.last))")
    }

    /// Equal weights are the common case once several terms share a seeded weight, and
    /// the head of this list is what fits the ASR bias budget — so the tie order must
    /// be the term, not whatever SQLite happens to return. Rows are inserted in
    /// reverse-alphabetical order, so insertion order and term order disagree. This
    /// pins THIS side's own ordering only: the in-memory cleanup sort is a separate
    /// decision under its own comparator, and the two are deliberately not compared.
    /// `Bravo` makes the tie case-sensitive — the pair `Bravo`/`bravo` differs only in
    /// a byte, which is exactly what an unspecified tie order reshuffles.
    /// Stated sensitivity: drop `Column("term").asc` from the ORDER BY → SQLite may
    /// return the tie group in ANY order and here returns `[delta, charlie, bravo,
    /// alpha, Bravo]` instead of `[Bravo, alpha, bravo, charlie, delta]` → RED. That
    /// order is not a rule to rely on: the 65-row test above, under the same mutation,
    /// gets its equal-weight group back in the OPPOSITE direction. Which way it falls
    /// is a query-plan detail — the reason the tie-break has to be explicit.
    @Test
    func equalWeightsAreOrderedByTerm() throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }

        try SeedImport.importRows([
            VocabularyRecord(term: "delta", category: "tech", weight: 4),
            VocabularyRecord(term: "charlie", category: "tech", weight: 4),
            VocabularyRecord(term: "zulu", category: "tech", weight: 9),
            VocabularyRecord(term: "bravo", category: "tech", weight: 4),
            VocabularyRecord(term: "alpha", category: "tech", weight: 4),
            VocabularyRecord(term: "Bravo", category: "tech", weight: 4),
        ], into: pool)

        let terms = GRDBPersonalizationSource(database: pool).vocabulary().map(\.term)
        #expect(terms == ["zulu", "Bravo", "alpha", "bravo", "charlie", "delta"],
                "weight still leads; equal weights must break on the term ascending; got \(terms)")
    }

    /// Applying a SYNTHETIC seed twice leaves `vocabulary` un-duplicated and
    /// `corrections` empty throughout (the real seed file is NEVER read in CI).
    /// Stated sensitivity: import without `INSERT OR IGNORE` → the re-apply either
    /// duplicates (no unique key) or throws SQLite-19 (unique key) → RED; write to
    /// `corrections` during import → count > 0 → RED.
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
