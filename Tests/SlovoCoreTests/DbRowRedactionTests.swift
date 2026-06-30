import Foundation
import Testing
import GRDB

import SlovoCore

// Epic 08 — AC-7 (SECURITY-CRITICAL, the 6th of 7 redaction channels): a DB-row
// value (vocabulary/profile) must NEVER reach the `RedactionSafeLog` sink.
//
// Contract under test (the Storage files must keep every DB-row payload OUT of
// the log; CURRENTLY the `_RedScaffold_Storage.swift` source logs only a coarse
// line, so this is GREEN — its RED is proven by MUTATION (log a fetched row
// `.public`), which ALSO REDs the L1 redaction lint).
//
// SEED-LEAK RULE (P1): the sentinel is a SYNTHETIC high-entropy string — no real
// key, no seed term, no private name.
@Suite("Epic 08 AC-7 DB-row redaction sentinel")
struct DbRowRedactionTests {
    private static let sentinel = "S3NT1NEL-DBROW-3f9a1c7e-DO-NOT-LOG"

    /// Store a unique sentinel as a `vocabulary` term, fetch it via the source
    /// with a capturing log sink, and assert NO captured line contains it.
    /// Stated sensitivity: add `log.event("\(record.term, privacy: .public)")` (or
    /// `String(describing: row)`) on a fetched row → the sentinel reaches the sink
    /// → RED; the L1 redaction lint ALSO REDs the `.public` of a payload. (GREEN on
    /// the scaffold which logs only a coarse line; RED proven out-of-band.)
    @Test
    func dbRowSentinelNeverReachesLogSink() throws {
        let path = TempDatabase.freshPath()
        defer { TempDatabase.remove(at: path) }
        let pool = try PersonalizationDatabase.open(at: path)
        try SeedImport.importRows(
            [VocabularyRecord(term: Self.sentinel, category: "tech", weight: 9)], into: pool
        )

        var captured: [String] = []
        let log = RedactionSafeLog(subsystem: "slovo", category: "storage-test") { captured.append($0) }
        let source = GRDBPersonalizationSource(database: pool, log: log)

        let terms = source.vocabulary(limit: 10)
        // Sanity: the sentinel WAS stored and fetched (guards a vacuous pass where
        // nothing was read).
        #expect(terms.contains { $0.term == Self.sentinel }, "precondition: the sentinel row must be fetched")

        let joined = captured.joined(separator: "\n")
        #expect(!joined.contains(Self.sentinel),
                "REDACTION LEAK: a DB-row value reached the log sink:\n\(joined)")
    }
}
