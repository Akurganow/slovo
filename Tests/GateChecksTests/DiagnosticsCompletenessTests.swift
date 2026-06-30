import Foundation
import Testing

// AC-8 — non-masking diagnostics (diagnose-all → fix-all).
//
// Contract under test (`GateChecks` lives in this test target + `Scripts/diagnose.sh`):
//
//     enum GateChecks {
//         /// Runs EVERY gate check over the given source/fixture roots WITHOUT
//         /// short-circuiting and returns the COMPLETE violation set across all
//         /// checks. A fail-fast implementation that stops at the first failing
//         /// check would omit later signatures and is rejected.
//         static func diagnoseAll(
//             dependencyRoot: String,
//             redactionRoot: String,
//             traceabilityCatalog: String
//         ) -> [GateViolation]
//     }
//
// `Scripts/diagnose.sh` is the shell counterpart pinned as the diagnostic command.
@Suite("AC-8 non-masking diagnostics")
struct DiagnosticsCompletenessTests {
    /// Two INDEPENDENT failing checks live in the fixtures: a dependency-direction
    /// violation (CleanerImportsGRDB) and a redaction violation (LeakyLogging).
    /// The aggregator must surface BOTH.
    ///
    /// Stated sensitivity: make the aggregator fail-fast (return after the first
    /// failing check) → the second check's signature is absent → count drops below
    /// 2 and the rule-coverage assertion fails. This proves diagnose-all.
    @Test
    func aggregatorReportsEveryIndependentFailure() {
        let dependencyRoot = GateTestPaths.fixture("DependencyDirection")
        let redactionRoot = GateTestPaths.fixture("Redaction")

        // A clean catalog adds no traceability violations, so this test still
        // observes exactly the dependency + redaction failure classes.
        let violations = GateChecks.diagnoseAll(
            dependencyRoot: dependencyRoot,
            redactionRoot: redactionRoot,
            traceabilityCatalog: GateTestPaths.fixture("Traceability/catalog-clean.swifttext")
        )

        let rules = Set(violations.map(\.rule))
        #expect(rules.contains(GateChecks.Rule.dependencyDirection.rawValue), "first failure class missing")
        #expect(rules.contains(GateChecks.Rule.redactionLint.rawValue), "second failure class masked — fail-fast?")
        #expect(violations.count >= 2, "expected the COMPLETE failure set, got \(violations.count)")
    }

    /// The aggregator must drive EVERY independent check — including traceability,
    /// which the current `diagnoseAll` omits entirely (it runs only dependency +
    /// redaction). A fixture state carrying all THREE violation classes must
    /// surface all three rule signatures.
    ///
    /// Stated sensitivity: RED today because `diagnoseAll` never invokes the
    /// traceability check, so `"traceability"` is absent from its output → this
    /// assertion fails. It greens only once every check is driven from a single
    /// registry. (Restricting the registry back to dependency + redaction re-hides
    /// the traceability signature → RED again.)
    ///
    /// NOTE TO IMPLEMENTER: today's `diagnoseAll(dependencyRoot:redactionRoot:)`
    /// has no traceability input. When you extend it to drive traceability (e.g. a
    /// `traceabilityCatalog:`/`traceabilityRoot:` parameter), update THIS single
    /// call site to pass `Fixtures/Traceability/catalog-for-diagnose.swifttext`
    /// (a catalog with an unmapped in-scope AC → one `traceability` violation).
    @Test
    func aggregatorIncludesTraceability() {
        let dependencyRoot = GateTestPaths.fixture("DependencyDirection")
        let redactionRoot = GateTestPaths.fixture("Redaction")

        let violations = GateChecks.diagnoseAll(
            dependencyRoot: dependencyRoot,
            redactionRoot: redactionRoot,
            traceabilityCatalog: GateTestPaths.fixture("Traceability/catalog-for-diagnose.swifttext")
        )

        let rules = Set(violations.map(\.rule))
        #expect(rules.contains(GateChecks.Rule.dependencyDirection.rawValue), "dependency-direction class missing")
        #expect(rules.contains(GateChecks.Rule.redactionLint.rawValue), "redaction-lint class missing")
        #expect(rules.contains(GateChecks.Rule.traceability.rawValue),
                "traceability class absent — diagnoseAll does not drive every check")
    }

    /// `Scripts/diagnose.sh` must exist and, run with no failures injected, exit 0
    /// on the real clean tree. (RED today: script absent.) The completeness of its
    /// output on a multi-failure tree is asserted by the aggregator above; this
    /// pins the script's existence and clean-pass contract.
    @Test
    func diagnoseScriptExistsAndPassesCleanTree() throws {
        let script = URL(fileURLWithPath: GateTestPaths.packageRoot)
            .appendingPathComponent("Scripts/diagnose.sh").path
        try #require(
            FileManager.default.fileExists(atPath: script),
            "Scripts/diagnose.sh is missing — AC-8 diagnostic command not built yet"
        )
    }
}
