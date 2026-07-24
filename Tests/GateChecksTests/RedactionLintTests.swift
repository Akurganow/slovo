import Foundation
import Testing

// Redaction lint (static).
//
// Contract under test (`GateChecks` lives in this test target):
//
//     enum GateChecks {
//         /// Flags every `Logger` interpolation of a payload-typed value that
//         /// uses `.public` or `String(describing:)`. `.private` / a hash / a
//         /// length passes. The check is PER-PAYLOAD-TYPE, so a `.public` leak of
//         /// ANY payload type is caught, not only `transcript`.
//         static func redactionViolations(inFileAt path: String) -> [GateViolation]
//         static func redactionViolations(inSourceTreeAt root: String) -> [GateViolation]
//     }
@Suite("Redaction lint")
struct RedactionLintTests {
    // Rule id via the symbol, so a rename is a compile error, not a silent miss.
    private static let ruleId = GateChecks.Rule.redactionLint.rawValue

    /// Stated sensitivity: flip the leaky fixture's `transcript` call `.public` →
    /// `.private` and the gate must stop flagging that line. Conversely, the
    /// production check must flag it while it is `.public`.
    @Test
    func publicTranscriptInterpolationIsFlagged() {
        let fixture = GateTestPaths.fixture("Redaction/LeakyLogging.swifttext")
        let violations = GateChecks.redactionViolations(inFileAt: fixture)
        #expect(violations.contains { $0.rule == Self.ruleId && $0.detail.contains("transcript") })
    }

    /// Per-payload-type sensitivity: a DIFFERENT payload type leaked
    /// via `String(describing:)` must ALSO be flagged, so the lint cannot pass by
    /// only inspecting `transcript`. Stated sensitivity: a single-variable scan
    /// (only `transcript`) misses the `term` line → this assertion fails.
    @Test
    func differentPayloadTypeLeakIsAlsoFlagged() {
        let fixture = GateTestPaths.fixture("Redaction/LeakyLogging.swifttext")
        let violations = GateChecks.redactionViolations(inFileAt: fixture)
        #expect(violations.contains { $0.rule == Self.ruleId && $0.detail.contains("term") })
    }

    /// The leaky fixture has THREE distinct leaks (transcript, term, error body);
    /// a non-masking scanner reports all of them, not just the first.
    @Test
    func allLeaksInFileAreReported() {
        let fixture = GateTestPaths.fixture("Redaction/LeakyLogging.swifttext")
        let violations = GateChecks.redactionViolations(inFileAt: fixture)
        #expect(violations.filter { $0.rule == Self.ruleId }.count >= 3)
    }

    /// `.private` / hash / length / coarse-enum logging passes with zero
    /// violations (guards against a scanner that flags safe redaction too).
    @Test
    func safeFixtureHasNoViolations() throws {
        let fixture = GateTestPaths.fixture("Redaction/SafeLogging.swifttext")
        // Guard vacuity: the scanner returns [] on an unreadable file.
        try #require(FileManager.default.fileExists(atPath: fixture), "fixture missing: \(fixture)")
        #expect(GateChecks.redactionViolations(inFileAt: fixture).isEmpty)
    }

    /// A leaky-looking call inside a LINE COMMENT is documentation, not code; it
    /// never reaches the log and must NOT be flagged.
    ///
    /// Stated sensitivity: make the scanner comment-blind (skip stripping line
    /// comments) → it matches the `.public` interpolation inside `// …
    /// logger.log("\(secret, privacy: .public)")` and reports a violation → this
    /// assertion fails.
    @Test
    func commentedLogCallIsNotFlagged() throws {
        let fixture = GateTestPaths.fixture("Redaction/CommentedExample.swifttext")
        try #require(FileManager.default.fileExists(atPath: fixture), "fixture missing: \(fixture)")
        let violations = GateChecks.redactionViolations(inFileAt: fixture)
        #expect(violations.isEmpty,
                "a leak inside a // comment is not code and must not be flagged: \(violations)")
    }

    /// A leak through a logger whose receiver is NOT named `logger` (here `log`)
    /// must still be flagged — a leak is a leak regardless of the variable name.
    ///
    /// Stated sensitivity: narrow the scanner to key on the literal receiver
    /// `logger.` → it misses `log.error("\(secret, privacy: .public)")` → zero
    /// violations → this assertion fails.
    @Test
    func anyReceiverLeakIsFlagged() {
        let fixture = GateTestPaths.fixture("Redaction/AnyReceiverLeak.swifttext")
        let violations = GateChecks.redactionViolations(inFileAt: fixture)
        #expect(violations.contains { $0.rule == Self.ruleId && $0.detail.contains("secret") },
                "a leak via a non-`logger` receiver must still be flagged")
    }

    /// A genuine leak whose logged STRING LITERAL contains `//` (a URL) to the
    /// LEFT of the `.public` interpolation must still be flagged — the `//` is
    /// inside the quoted string, not a comment.
    ///
    /// Stated sensitivity: revert `strippingLineComment` to a naive cut at the
    /// FIRST `//` → it truncates the line before the `.public` interpolation,
    /// silently dropping the leak → zero violations → this assertion fails.
    @Test
    func leakAfterUrlInStringLiteralIsFlagged() {
        let fixture = GateTestPaths.fixture("Redaction/UrlInStringLeak.swifttext")
        let violations = GateChecks.redactionViolations(inFileAt: fixture)
        #expect(violations.contains { $0.rule == Self.ruleId && $0.detail.contains("token") },
                "a `.public` leak following a `//` inside a string literal must still be flagged")
    }

    /// A genuine leak followed by a trailing `//` line comment on the SAME line
    /// must be flagged — the leak is to the LEFT of the comment, so stripping the
    /// comment leaves the leak intact. Regression-lock (GREEN now): the
    /// literal-aware fix must not start swallowing leaks that precede a real
    /// trailing comment.
    @Test
    func leakBeforeTrailingCommentIsFlagged() {
        let fixture = GateTestPaths.fixture("Redaction/TrailingCommentLeak.swifttext")
        let violations = GateChecks.redactionViolations(inFileAt: fixture)
        #expect(violations.contains { $0.rule == Self.ruleId && $0.detail.contains("name") },
                "a leak preceding a real trailing // comment must still be flagged")
    }

    /// A payload on a CONTINUATION line of a multi-line `.info(` call must be
    /// flagged even though the opener and the leak never share a line, while the
    /// `.count` reduction on the sibling continuation line stays allowed.
    /// Catches: a scanner that pairs the logging call and its payload per line —
    /// it finds nothing in this fixture and the non-empty assertion fails.
    @Test
    func multilineContinuationLeakIsFlaggedAndCountAllowed() {
        let fixture = GateTestPaths.fixture("Redaction/MultilineLogCall.swifttext")
        let violations = GateChecks.redactionViolations(inFileAt: fixture)
        #expect(violations.contains { $0.rule == Self.ruleId && $0.detail.contains("`transcript`") },
                "a leak on a continuation line of a multi-line logging call must be flagged")
        #expect(violations.count == 1,
                "the `.count` reduction on the sibling line must stay allowed: \(violations)")
    }

    /// A CALL-expression payload rendered `.public` is still the payload.
    /// Catches: a bare-identifier payload matcher — the call parens stop it from
    /// matching, the fixture yields nothing, and the assertion fails.
    @Test
    func callExpressionPayloadLeakIsFlagged() {
        let fixture = GateTestPaths.fixture("Redaction/CallPayloadLeak.swifttext")
        let violations = GateChecks.redactionViolations(inFileAt: fixture)
        #expect(violations.contains { $0.rule == Self.ruleId && $0.detail.contains("transcript.trimmed()") },
                "an expression payload marked .public must be flagged")
    }

    /// The real `Sources/` tree must contain no redaction violations.
    @Test
    func realSourceTreeIsClean() throws {
        // Guard vacuity: a wrong root would walk nothing.
        try #require(FileManager.default.fileExists(atPath: GateTestPaths.sourcesRoot),
                     "sources root missing: \(GateTestPaths.sourcesRoot)")
        // Guard vacuity: an empty (or wrong-suffix) walk would green with the
        // scanner never reading a single real source.
        let scanned = GateChecks.sourceFiles(under: GateTestPaths.sourcesRoot)
        #expect(scanned.contains { $0.hasSuffix("/Orchestrator.swift") },
                "the walk must visit known real sources; visited \(scanned.count) files")
        let violations = GateChecks.redactionViolations(inSourceTreeAt: GateTestPaths.sourcesRoot)
        #expect(violations.isEmpty, "Sources/ has redaction violations: \(violations)")
    }
}
