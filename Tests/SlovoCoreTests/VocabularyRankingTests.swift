import Foundation
import GRDB
import Testing

@testable import SlovoCore

// vocabulary() = BiasRanker order over stored misses; term_misses read is
// separately fallible and degrades to weight order, never to an empty
// vocabulary. Spec section "Ranking".
@Suite("Vocabulary bias ranking")
struct VocabularyRankingTests {
    private static func openStore() throws -> (pool: DatabasePool, teardown: () -> Void) {
        let path = TempDatabase.freshPath()
        let pool = try PersonalizationDatabase.open(at: path, passphrase: TempDatabase.passphrase)
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
        try GRDBPersonalizationSource(database: pool).addVocabulary([
            VocabularyRecord(term: "stable", category: "term", weight: 2),
            VocabularyRecord(term: "missed", category: "term", weight: 1),
        ])
        await GRDBTermMissStore(database: pool).recordMisses(["missed"])
        var events: [String] = []
        let log = RedactionSafeLog(subsystem: "test", category: "ranking") { events.append($0) }

        let terms = GRDBPersonalizationSource(database: pool, log: log).vocabulary().map(\.term)

        #expect(terms == ["missed", "stable"])
        // Both terms move (they swap), over the single stored event.
        #expect(events.contains("vocabulary ranked moved=2 eventRows=1"))
    }

    /// THE degradation pin: a broken term_misses table yields weight order
    /// with the vocabulary INTACT — never an empty read (an empty read would
    /// strip the cleanup glossary too). With no ranking, the SQL ORDER BY is
    /// the final order, so the equal-weight group, inserted in reverse, pins
    /// the SQL term tie-break in byte order (`Bravo` before `bravo`).
    /// Stated sensitivity: fold the events query into the same
    /// `database.read` as the vocabulary fetch → the DROP kills both →
    /// vocabulary comes back [] → RED; delete the `term miss read failed`
    /// `log.event` → the degradation becomes silent → RED; drop
    /// `Column("term").asc` from the vocabulary ORDER BY → under the
    /// migrator's ascending `(weight, term)` index the tie group comes back
    /// reversed → RED.
    @Test
    func brokenEventsTableDegradesToWeightOrder() throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }
        try GRDBPersonalizationSource(database: pool).addVocabulary([
            VocabularyRecord(term: "alpha", category: "term", weight: 1),
            VocabularyRecord(term: "zulu", category: "term", weight: 5),
            VocabularyRecord(term: "delta", category: "term", weight: 3),
            VocabularyRecord(term: "charlie", category: "term", weight: 3),
            VocabularyRecord(term: "bravo", category: "term", weight: 3),
            VocabularyRecord(term: "Bravo", category: "term", weight: 3),
        ])
        try pool.write { db in try db.execute(sql: "DROP TABLE term_misses") }
        var events: [String] = []
        let log = RedactionSafeLog(subsystem: "test", category: "ranking") { events.append($0) }

        let terms = GRDBPersonalizationSource(database: pool, log: log).vocabulary().map(\.term)

        #expect(terms == ["zulu", "Bravo", "bravo", "charlie", "delta", "alpha"])
        // Degrading silently would hide a broken feedback loop indefinitely.
        #expect(events.contains("term miss read failed; weight order"))
    }

    /// A failed vocabulary read returns no terms and says so in the log, with a
    /// line an empty table never writes. The captured lines are compared whole,
    /// so a line that carried the error or a row value would fail too.
    /// Stated sensitivity: revert the read to `(try? database.read { … }) ?? []`
    /// → the log shows `vocabulary fetched` and `len=0`, as for an empty table,
    /// and no `vocabulary read failed` → RED.
    @Test
    func failedVocabularyReadLogsTheFailure() throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }
        try GRDBPersonalizationSource(database: pool).addVocabulary([
            VocabularyRecord(term: "alpha", category: "term", weight: 1),
        ])
        try pool.write { db in try db.execute(sql: "DROP TABLE vocabulary") }
        var events: [String] = []
        let log = RedactionSafeLog(subsystem: "test", category: "ranking") { events.append($0) }

        let terms = GRDBPersonalizationSource(database: pool, log: log).vocabulary()

        #expect(terms.isEmpty)
        #expect(events == ["vocabulary read failed"])
    }

    /// Settings' allVocabulary() intentionally KEEPS weight order while
    /// vocabulary() re-ranks — the reads now diverge by design.
    /// Stated sensitivity: route allVocabulary() through BiasRanker too →
    /// the missed term leads there as well → RED.
    @Test
    func allVocabularyKeepsWeightOrder() async throws {
        let (pool, teardown) = try Self.openStore()
        defer { teardown() }
        try GRDBPersonalizationSource(database: pool).addVocabulary([
            VocabularyRecord(term: "stable", category: "term", weight: 2),
            VocabularyRecord(term: "missed", category: "term", weight: 1),
        ])
        await GRDBTermMissStore(database: pool).recordMisses(["missed"])

        let rows = try GRDBPersonalizationSource(database: pool).allVocabulary().map(\.term)

        #expect(rows == ["stable", "missed"])
    }
}
