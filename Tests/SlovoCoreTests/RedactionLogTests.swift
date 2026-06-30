import Foundation
import Testing

@testable import SlovoCore

// T4 (supports AC-5; spec §11) — behavioral test of the redaction-safe logging
// wrapper. Runtime complement to the static AC-5 lint.
//
// Contract under test (implementer builds in `SlovoCore`):
//
//     public struct RedactionSafeLog {
//         /// `sink` defaults to writing through `os.Logger`; tests inject a
//         /// capturing sink to observe exactly what would be emitted.
//         public init(subsystem: String, category: String, sink: ((String) -> Void)?)
//
//         /// Static, NON-payload text only — emitted verbatim.
//         public func event(_ message: String)
//
//         /// Emits a payload's LENGTH to the sink, never its value.
//         public func logLength(of value: some Collection)
//
//         /// Emits a stable short HASH to the sink for correlation, never the value.
//         public func logHash(of value: String)
//
//         /// Pure helpers returning the redacted form (also used by the lint's
//         /// safe fixture): a short stable hash and a length.
//         public static func hashed(_ value: String) -> String
//         public static func length(of value: some Collection) -> Int
//     }
@Suite("T4 redaction-safe logging wrapper")
struct RedactionLogTests {
    /// A high-entropy sentinel that must NEVER appear in any emitted line.
    private static let sentinel = "S3NT1NEL-9f2a4c8e-transcript-body-DO-NOT-LOG"

    /// Stated sensitivity: make `hashed`/`length` emit the raw string instead of
    /// its hash/length → the sentinel appears in the captured sink → RED. As long
    /// as the helpers redact, the sentinel is absent and the test passes.
    @Test
    func payloadValueNeverReachesSink() {
        var captured: [String] = []
        let log = RedactionSafeLog(subsystem: "com.slovo.test", category: "redaction") {
            captured.append($0)
        }

        log.logLength(of: Self.sentinel)
        log.logHash(of: Self.sentinel)
        log.event("pipeline step completed")  // static text is allowed verbatim

        let joined = captured.joined(separator: "\n")
        #expect(!joined.contains(Self.sentinel),
                "raw payload leaked into the log sink: \(joined)")
        // Sanity: something WAS emitted (guards against a no-op sink that passes
        // vacuously by never emitting anything at all).
        #expect(!captured.isEmpty, "wrapper emitted nothing — vacuous pass")
    }

    /// The hash helper must be redacting (not identity) AND stable for correlation.
    /// Stated sensitivity: make `hashed` return its input unchanged → equality with
    /// the raw value holds → RED.
    @Test
    func hashedRedactsAndIsStable() {
        let hashedA = RedactionSafeLog.hashed(Self.sentinel)
        let hashedB = RedactionSafeLog.hashed(Self.sentinel)
        #expect(hashedA == hashedB, "hash must be stable for correlation")
        #expect(hashedA != Self.sentinel, "hash must not equal the raw value")
        #expect(!hashedA.contains(Self.sentinel), "hash must not embed the raw value")
    }

    /// The length helper reports the count, never the content.
    /// Stated sensitivity: make `length(of:)` return 0 or the string → mismatch.
    @Test
    func lengthReportsCountNotContent() {
        #expect(RedactionSafeLog.length(of: Self.sentinel) == Self.sentinel.count)
    }
}
