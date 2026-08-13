import Foundation
import GRDB
import Testing

import SlovoCore

// vocabulary() = BiasRanker order over stored misses; term_misses read is
// separately fallible and degrades to weight order, never to an empty
// vocabulary. Spec section "Ranking".
@Suite("Vocabulary bias ranking")
struct VocabularyRankingTests {
    private static func openStore() throws -> (pool: DatabasePool, teardown: () -> Void) {
        let path = TempDatabase.freshPath()
        let pool = try PersonalizationDatabase.open(at: path)
        return (pool, { TempDatabase.remove(at: path) })
    }

    /// A recent miss lifts a weight-1 term over a weight-2 peer, and the read
    /// reports the loop's coarse counts — the whole feedback surface the owner
    /// has for a mis-tuned constant, so it is pinned rather than left
    /// deletable-with-tests-green.
    /// Stated sensitivity: return `terms` instead of the ranked array in
    /// `vocabulary()` → weight order → RED; delete the `vocabulary ranked`
    /// `log.event` → the line assertion → RED.
    @Test
    func recentMissReordersTheRead() async throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }
        try SeedImport.importRows([
            VocabularyRecord(term: "stable", category: "term", weight: 2),
            VocabularyRecord(term: "missed", category: "term", weight: 1),
        ], into: pool)
        await GRDBTermMissStore(database: pool).recordMisses(["missed"])
        var events: [String] = []
        let log = RedactionSafeLog(subsystem: "test", category: "ranking") { events.append($0) }

        let terms = GRDBPersonalizationSource(database: pool, log: log).vocabulary().map(\.term)

        #expect(terms == ["missed", "stable"])
        // Both terms move (they swap), over the single stored event.
        #expect(events.contains("vocabulary ranked moved=2 eventRows=1"))
    }

    /// No events → exactly today's order (weight desc, term asc): the ranking
    /// is invisible until a miss exists. Pins that existing consumers see no
    /// change on a fresh database. (The weight/term tie-break itself is pinned
    /// in BiasRankerTests.tieBreaksByWeightThenTerm — distinct weights here
    /// pin the score ordering.)
    /// Stated sensitivity: flip `rank`'s score comparator to ascending → the
    /// sequence reverses → RED.
    @Test
    func noEventsPreservesWeightOrder() throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }
        try SeedImport.importRows([
            VocabularyRecord(term: "alpha", category: "term", weight: 1),
            VocabularyRecord(term: "zulu", category: "term", weight: 5),
            VocabularyRecord(term: "beta", category: "term", weight: 3),
        ], into: pool)

        let terms = GRDBPersonalizationSource(database: pool).vocabulary().map(\.term)

        #expect(terms == ["zulu", "beta", "alpha"])
    }

    /// THE degradation pin: a broken term_misses table yields weight order
    /// with the vocabulary INTACT — never an empty read (an empty read would
    /// strip the cleanup glossary too).
    /// Stated sensitivity: fold the events query into the same
    /// `database.read` as the vocabulary fetch → the DROP kills both →
    /// vocabulary comes back [] → RED; delete the `term miss read failed`
    /// `log.event` → the degradation becomes silent → RED.
    @Test
    func brokenEventsTableDegradesToWeightOrder() throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }
        try SeedImport.importRows([
            VocabularyRecord(term: "alpha", category: "term", weight: 1),
            VocabularyRecord(term: "zulu", category: "term", weight: 5),
        ], into: pool)
        try pool.write { db in try db.execute(sql: "DROP TABLE term_misses") }
        var events: [String] = []
        let log = RedactionSafeLog(subsystem: "test", category: "ranking") { events.append($0) }

        let terms = GRDBPersonalizationSource(database: pool, log: log).vocabulary().map(\.term)

        #expect(terms == ["zulu", "alpha"])
        // Degrading silently would hide a broken feedback loop indefinitely.
        #expect(events.contains("term miss read failed; weight order"))
    }

    /// Settings' allVocabulary() intentionally KEEPS weight order while
    /// vocabulary() re-ranks — the reads now diverge by design.
    /// Stated sensitivity: route allVocabulary() through BiasRanker too →
    /// the missed term leads there as well → RED.
    @Test
    func allVocabularyKeepsWeightOrder() async throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }
        try SeedImport.importRows([
            VocabularyRecord(term: "stable", category: "term", weight: 2),
            VocabularyRecord(term: "missed", category: "term", weight: 1),
        ], into: pool)
        await GRDBTermMissStore(database: pool).recordMisses(["missed"])

        let rows = try GRDBPersonalizationSource(database: pool).allVocabulary().map(\.term)

        #expect(rows == ["stable", "missed"])
    }
}
