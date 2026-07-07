import Foundation
import Testing

// AC-4 — dependency-direction gate.
//
// Contract under test (the implementer must build this in `SlovoCore`):
//
//     enum GateChecks {
//         /// A role-tagged source file (Cleaner/Transcriber/Injector) must not
//         /// `import GRDB`, and a backend must not import a sibling backend.
//         /// Returns one violation per offending import; empty == clean.
//         static func dependencyViolations(inFileAt path: String) -> [GateViolation]
//         static func dependencyViolations(inSourceTreeAt root: String) -> [GateViolation]
//     }
//
//     struct GateViolation: Equatable, Sendable {
//         let file: String     // absolute path of the offending file
//         let rule: String     // stable rule id, e.g. "dependency-direction"
//         let detail: String   // human-readable specifics
//     }
//
// The tests below are RED today because `GateChecks` does not exist. They are
// behavior-specific, not "package doesn't compile": each asserts the SHAPE of the
// result the production scanner must return.
@Suite("AC-4 dependency direction")
struct DependencyDirectionTests {
    // Rule id via the symbol, so a rename is a compile error, not a silent miss.
    private static let ruleId = GateChecks.Rule.dependencyDirection.rawValue

    /// Stated sensitivity: remove the `import GRDB` match from the production
    /// scanner → this Cleaner fixture wrongly passes → the meta-assertion
    /// (RED fixture MUST be flagged) fails.
    @Test
    func cleanerImportingGRDBIsFlagged() {
        let fixture = GateTestPaths.fixture("DependencyDirection/CleanerImportsGRDB.swifttext")
        let violations = GateChecks.dependencyViolations(inFileAt: fixture)
        #expect(violations.contains { $0.rule == Self.ruleId && $0.detail.contains("GRDB") })
    }

    /// Stated sensitivity: a backend importing another backend must RED; drop the
    /// sibling-backend rule and this fixture wrongly passes.
    @Test
    func backendImportingSiblingBackendIsFlagged() {
        let fixture = GateTestPaths.fixture("DependencyDirection/TranscriberImportsBackend.swifttext")
        let violations = GateChecks.dependencyViolations(inFileAt: fixture)
        #expect(violations.contains { $0.rule == Self.ruleId })
    }

    /// A role-tagged source importing only Foundation must produce zero violations
    /// (guards against an over-eager scanner that flags everything).
    @Test
    func cleanFixtureHasNoViolations() throws {
        let fixture = GateTestPaths.fixture("DependencyDirection/CleanerClean.swifttext")
        // Guard vacuity: the scanner returns [] on an unreadable file.
        try #require(FileManager.default.fileExists(atPath: fixture), "fixture missing: \(fixture)")
        #expect(GateChecks.dependencyViolations(inFileAt: fixture).isEmpty)
    }

    /// Role is determined by LOCATION, not by a filename substring. A real role
    /// source under a role DIRECTORY (`Cleaners/Orchestrator.swifttext`) whose name
    /// lacks the "Cleaner" substring must still be flagged for importing GRDB.
    ///
    /// Stated sensitivity: this is RED on the current filename-only detector (it
    /// keys off `name.contains("Cleaner"/"Transcriber"/"Injector")`, so
    /// `Orchestrator.swifttext` is not seen as a role module and its `import GRDB`
    /// is missed → zero violations → this assertion fails). It greens only once
    /// detection policies by directory/path.
    @Test
    func roleSourceInRoleDirectoryIsFlaggedDespiteName() {
        let fixture = GateTestPaths.fixture("DependencyDirection/Cleaners/Orchestrator.swifttext")
        let violations = GateChecks.dependencyViolations(inFileAt: fixture)
        #expect(violations.contains { $0.rule == Self.ruleId && $0.detail.contains("GRDB") },
                "a role source under Cleaners/ must be flagged regardless of its filename")
    }

    /// A TEST file named `CleanerTests.swifttext` is NOT a role module — its name
    /// merely contains "Cleaner" because it tests a Cleaner. A test importing GRDB
    /// is legitimate and must NOT be flagged.
    ///
    /// Stated sensitivity: this is RED on the current detector, which substring-
    /// matches "Cleaner" and so false-positives this test file (it reports a GRDB
    /// violation) → this assertion fails. It greens only once detection uses
    /// location plus a word-boundary fallback that excludes `*Tests`/`Mock*`.
    @Test
    func testShapedNameIsNotFalsePositive() throws {
        let fixture = GateTestPaths.fixture("DependencyDirection/CleanerTests.swifttext")
        try #require(FileManager.default.fileExists(atPath: fixture), "fixture missing: \(fixture)")
        let violations = GateChecks.dependencyViolations(inFileAt: fixture)
        #expect(!violations.contains { $0.rule == Self.ruleId },
                "a CleanerTests file is a test, not a role module — it must not be flagged")
    }

    /// The real `Sources/` tree must already obey the rule.
    @Test
    func realSourceTreeIsClean() throws {
        // Guard vacuity: a wrong root would walk nothing.
        try #require(FileManager.default.fileExists(atPath: GateTestPaths.sourcesRoot),
                     "sources root missing: \(GateTestPaths.sourcesRoot)")
        let violations = GateChecks.dependencyViolations(inSourceTreeAt: GateTestPaths.sourcesRoot)
        #expect(violations.isEmpty, "Sources/ has dependency-direction violations: \(violations)")
    }

    /// Epic 08 (positive): a Storage-layer source MAY import GRDB — Storage is the
    /// ONE place persistence is allowed; it is not a role module. The gate must
    /// return ZERO violations for it.
    /// Stated sensitivity: broaden `isRoleTagged` to also tag `Storage/` (or a
    /// `PersonalizationSource` filename) → this Storage fixture is wrongly flagged
    /// → the "empty" assertion fails → RED. (GREEN today; locks the invariant
    /// against an over-eager future gate change.)
    @Test
    func storageMayImportGRDB() throws {
        let fixture = GateTestPaths.fixture("DependencyDirection/Storage/GRDBPersonalizationSource.swifttext")
        try #require(FileManager.default.fileExists(atPath: fixture), "fixture missing: \(fixture)")
        let violations = GateChecks.dependencyViolations(inFileAt: fixture)
        #expect(violations.isEmpty,
                "a Storage source may import GRDB — it must NOT be flagged; got \(violations)")
    }
}
