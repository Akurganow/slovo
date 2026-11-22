import Foundation
import Testing
import GRDB

import SlovoCore

// Dedup on (term, category) with corrections inert, and full ordering by weight.
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
    /// `term` + same `category` dedups to one, and adding vocabulary never
    /// writes `corrections` (inert in v1).
    /// Stated sensitivity: declare `UNIQUE(term)` (drop `category`) → the
    /// two-category case collapses to 1 → RED; insert without `INSERT OR
    /// IGNORE` → the re-add throws SQLite-19 → RED; write to `corrections`
    /// during the add → count > 0 → RED.
    @Test
    func dedupIsPerTermAndCategory() throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }

        try GRDBPersonalizationSource(database: pool).addVocabulary([
            VocabularyRecord(term: "GitHub", category: "tool"),
            VocabularyRecord(term: "GitHub", category: "org"),   // same term, different category → BOTH survive
        ])
        let twoCategories = try pool.read { db in try VocabularyRecord.fetchCount(db) }
        #expect(twoCategories == 2, "the same term in two categories must both survive (UNIQUE(term, category)); got \(twoCategories)")

        // Same (term, category) inserted again must dedup to one (no extra row).
        try GRDBPersonalizationSource(database: pool).addVocabulary([VocabularyRecord(term: "GitHub", category: "tool")])
        let afterDuplicate = try pool.read { db in
            try VocabularyRecord.filter(Column("term") == "GitHub" && Column("category") == "tool").fetchCount(db)
        }
        #expect(afterDuplicate == 1, "the same (term, category) must dedup to a single row; got \(afterDuplicate)")

        let corrections = try pool.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM corrections") ?? -1 }
        #expect(corrections == 0, "adding vocabulary must never write to corrections (inert in v1); got \(corrections)")
    }

    /// `vocabulary()` returns EVERY stored term in descending weight order — the read
    /// is uncapped, and its consumers (the cleanup prompt, the ASR bias head) budget
    /// it themselves. Five distinct-weight anchors pin the ordering; 60 weight-0
    /// fillers sit below them so the fixture outgrows every plausible cap. With
    /// `term_misses` readable, `BiasRanker.rank` re-sorts the whole read, so the
    /// order asserted here is the ranker's; the SQL ORDER BY is pinned on the
    /// degraded path, in `VocabularyRankingTests.brokenEventsTableDegradesToWeightOrder`.
    /// Stated sensitivity: reintroduce `.limit(50)` → 50 rows instead of 65, and the
    /// tail is filler-45 rather than filler-60 → RED; `.limit(10)` and `.limit(25)`
    /// redden the same two expectations. A 5-row fixture (the version this replaced)
    /// let every one of those caps pass. Flip the ranker's score comparator to
    /// ascending → the anchor head stops being [w9, w7, w5, w3, w1] → RED.
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
        try GRDBPersonalizationSource(database: pool).addVocabulary(anchors + fillers)

        let terms = GRDBPersonalizationSource(database: pool).vocabulary().map(\.term)
        #expect(terms.count == 65, "all 65 stored rows must come back uncapped; got \(terms.count)")
        #expect(Array(terms.prefix(5)) == ["w9", "w7", "w5", "w3", "w1"],
                "the weighted anchors must lead in descending weight order; got \(Array(terms.prefix(5)))")
        #expect(terms.last == "filler-60",
                "the lowest-weight tail must survive the read; got \(String(describing: terms.last))")
    }

    /// Equal weights are the common case once several terms share a weight, and the
    /// head of this list is what fits the ASR bias budget — so the tie order must be
    /// the term, in byte order. Rows are inserted in reverse-alphabetical order, so
    /// insertion order and term order disagree. This pins THIS side's own ordering
    /// only: the in-memory cleanup sort is a separate decision under its own
    /// comparator, and the two are deliberately not compared. `Bravo` makes the tie
    /// case-sensitive — the pair `Bravo`/`bravo` differs only in a byte. With
    /// `term_misses` readable, `BiasRanker.rank` sorts the result, so this pins the
    /// ranker's term tie-break; the tie-break cases in `BiasRankerTests` use
    /// lower-case terms only.
    /// Stated sensitivity: make the ranker's term tie-break case-insensitive
    /// (compare `lowercased()` scalars) → `alpha` sorts before `Bravo` → RED.
    @Test
    func equalWeightsAreOrderedByTerm() throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }

        try GRDBPersonalizationSource(database: pool).addVocabulary([
            VocabularyRecord(term: "delta", category: "tech", weight: 4),
            VocabularyRecord(term: "charlie", category: "tech", weight: 4),
            VocabularyRecord(term: "zulu", category: "tech", weight: 9),
            VocabularyRecord(term: "bravo", category: "tech", weight: 4),
            VocabularyRecord(term: "alpha", category: "tech", weight: 4),
            VocabularyRecord(term: "Bravo", category: "tech", weight: 4),
        ])

        let terms = GRDBPersonalizationSource(database: pool).vocabulary().map(\.term)
        #expect(terms == ["zulu", "Bravo", "alpha", "bravo", "charlie", "delta"],
                "weight still leads; equal weights must break on the term ascending; got \(terms)")
    }
}
