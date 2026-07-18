import Foundation
import Testing

// Never-self-restart gate: the immediate install + relaunch trigger
// (`installDownloadedUpdateAndRelaunch`) may have EXACTLY ONE invocation site in
// the app target — the user-initiated Restart click. Zero means the Restart
// path is missing; two or more re-open the self-restart door the design closed.
@Suite("Single relaunch call site")
struct SingleRelaunchCallSiteTests {
    private static let ruleId = GateChecks.Rule.singleRelaunchCallSite.rawValue

    /// Clean fixture tree: the definition plus exactly one invocation → zero
    /// violations.
    /// Stated sensitivity: count the `func` definition itself as a call site →
    /// the clean tree reads as two sites → wrongly flagged → RED.
    @Test
    func cleanTreeWithOneInvocationPasses() throws {
        let root = GateTestPaths.fixture("SingleRelaunch/Clean")
        try #require(FileManager.default.fileExists(atPath: root), "fixture missing: \(root)")
        let violations = GateChecks.singleRelaunchViolations(inSourceTreeAt: root)
        #expect(violations.isEmpty, "the clean tree must pass; got \(violations)")
    }

    /// RED fixture tree: a second invocation site must be flagged — the
    /// meta-assertion that proves the scanner can go red at all (house fixture
    /// discipline).
    /// Stated sensitivity: drop the more-than-one branch (or stop scanning) →
    /// the rigged second call site sails through → this fails.
    @Test
    func secondInvocationSiteIsFlagged() throws {
        let root = GateTestPaths.fixture("SingleRelaunch/SecondCallSite")
        try #require(FileManager.default.fileExists(atPath: root), "fixture missing: \(root)")
        let violations = GateChecks.singleRelaunchViolations(inSourceTreeAt: root)
        #expect(violations.count == 2, "both offending sites must be reported; got \(violations)")
        #expect(violations.allSatisfy { $0.rule == Self.ruleId })
    }

    /// The real app target carries exactly one invocation site — the
    /// user-initiated Restart click calling the coordinator (proven RED before
    /// the coordinator existed: the scanner reported the missing-Restart-path
    /// violation on the then-empty tree).
    /// Stated sensitivity: add a second call site anywhere under
    /// Sources/slovo, or remove the Restart action → RED.
    @Test
    func appTargetHasExactlyOneRelaunchInvocation() throws {
        let appRoot = URL(fileURLWithPath: GateTestPaths.sourcesRoot)
            .appendingPathComponent("slovo").path
        try #require(FileManager.default.fileExists(atPath: appRoot), "app target missing: \(appRoot)")
        let violations = GateChecks.singleRelaunchViolations(inSourceTreeAt: appRoot)
        #expect(violations.isEmpty, "Sources/slovo must have exactly one relaunch invocation: \(violations)")
    }
}
