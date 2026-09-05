import Combine
import Foundation
import Testing

// The reusable CI workflow is the whole local gate, not a subset of it. Pull
// requests, releases, and dev builds all pass through swift.yml, while the
// analyzer, plist, shell-syntax, and explicit-import stages exist only in
// Scripts/diagnose.sh (via Scripts/lint.sh) — so a workflow that runs a bare
// `swift test` instead lets a violation of any of them reach main unseen, as
// it did for the repository's first two months.
@Suite("CI gate contract")
struct CIGateContractTests {
    /// Stated sensitivity: replace `run: Scripts/diagnose.sh` in swift.yml with
    /// `swift test` (or any other subset of the gate) → RED.
    @Test
    func reusableWorkflowRunsTheWholeLocalGate() throws {
        let workflow = try String(
            contentsOf: ReleaseScriptRunner.packageRoot.appending(path: ".github/workflows/swift.yml"),
            encoding: .utf8
        )

        #expect(workflow.contains("run: Scripts/diagnose.sh"))
    }
}
