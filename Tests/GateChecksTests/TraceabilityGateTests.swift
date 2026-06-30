import Foundation
import Testing

// AC-7 — traceability gate.
//
// Contract under test (`GateChecks` lives in this test target):
//
//     enum GateChecks {
//         /// Reads a catalog mapping in-scope AC ids → covering test, plus test
//         /// bodies. Flags two defect classes:
//         ///   - an in-scope AC with NO mapped test ("missing");
//         ///   - an AC mapped to a placeholder/assertion-free body ("vacuous").
//         static func traceabilityViolations(catalogAt path: String) -> [GateViolation]
//     }
@Suite("AC-7 traceability gate")
struct TraceabilityGateTests {
    // Rule id via the symbol, so a rename is a compile error, not a silent miss.
    private static let ruleId = GateChecks.Rule.traceability.rawValue

    private static var defectiveCatalog: String {
        GateTestPaths.fixture("Traceability/catalog.swifttext")
    }

    /// Stated sensitivity: remove the in-scope AC that has no mapped test and the
    /// "missing" violation disappears. The gate must report a missing-mapping
    /// violation that names the unmapped AC.
    @Test
    func missingMappingIsFlagged() {
        let violations = GateChecks.traceabilityViolations(catalogAt: Self.defectiveCatalog)
        #expect(violations.contains { violation in
            violation.rule == Self.ruleId && violation.detail.contains("FIXTURE-AC-MISSING")
        })
    }

    /// Stated sensitivity: an AC mapped to a `#expect(true)` / assertion-free body
    /// must RED — the gate detects "named but vacuous", not only absent mappings.
    /// Replace the placeholder body with a real assertion → this violation clears.
    @Test
    func vacuousPlaceholderBodyIsFlagged() {
        let violations = GateChecks.traceabilityViolations(catalogAt: Self.defectiveCatalog)
        #expect(violations.contains { violation in
            violation.rule == Self.ruleId && violation.detail.contains("FIXTURE-AC-VACUOUS")
        })
    }

    /// The AC with a real assertion must NOT be flagged (no false positive).
    @Test
    func realAssertionACIsNotFlagged() {
        let violations = GateChecks.traceabilityViolations(catalogAt: Self.defectiveCatalog)
        #expect(!violations.contains { $0.detail.contains("FIXTURE-AC-GOOD") })
    }

    /// A catalog where every in-scope AC maps to a real assertion passes clean.
    @Test
    func cleanCatalogHasNoViolations() {
        let clean = GateTestPaths.fixture("Traceability/catalog-clean.swifttext")
        #expect(GateChecks.traceabilityViolations(catalogAt: clean).isEmpty)
    }
}
