import Foundation
import Testing

// Epic 08 — AC-8: `data/schema.sql` must NOT carry the WITHDRAWN day-one prompt-
// caching claim (P13/I6: caching is a bonus, not a day-one driver), and must
// state the term-preservation purpose.
//
// RED RIGHT NOW (no mutation needed): the real `data/schema.sql:6` still says
// "the prompt cache starts paying off from day one." The implementer (WL-
// authorized, a tracked file) removes that wording → GREEN.
@Suite("Epic 08 AC-8 schema comment")
struct SchemaCommentTests {
    /// `<pkg>/data/schema.sql` — derived from this file's path so it is correct
    /// regardless of the launch cwd.
    private static var schemaPath: String {
        URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()  // SlovoCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // <pkg>
            .appendingPathComponent("data/schema.sql")
            .path
    }

    /// The withdrawn day-one-caching wording must be ABSENT.
    /// Stated sensitivity: leave (or re-introduce) the "pay…off from day one" /
    /// "cache … day one" phrasing → the forbidden-phrase scan matches → RED.
    /// (RED against the real file today — the wording is still present.)
    @Test
    func schemaHasNoDayOneCachingClaim() throws {
        let schema = try String(contentsOfFile: Self.schemaPath, encoding: .utf8).lowercased()
        // Forbidden phrasings of the withdrawn claim (case-insensitive).
        let forbidden = ["paying off from day one", "pay off from day one", "cache starts paying", "from day one"]
        for phrase in forbidden {
            #expect(!schema.contains(phrase),
                    "data/schema.sql still carries the WITHDRAWN day-one-caching claim: found \"\(phrase)\"")
        }
    }

    /// The `vocabulary` Purpose must still state term-preservation (the real
    /// reason the table exists) — guards against deleting the comment wholesale.
    @Test
    func schemaStatesTermPreservationPurpose() throws {
        let schema = try String(contentsOfFile: Self.schemaPath, encoding: .utf8).lowercased()
        #expect(schema.contains("preserve"),
                "data/schema.sql must state the term-preservation purpose of the vocabulary table")
    }
}
