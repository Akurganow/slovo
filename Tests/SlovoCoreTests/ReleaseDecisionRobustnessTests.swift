import Foundation
import Testing

// Robustness pins for Scripts/release-decision.sh in git mode: a git failure
// (not a repository, fork/EAGAIN under load) must never be conflated with the
// legitimate "no release tag yet → first release" branch. The conflation is a
// live flake source: `git describe` failing for ANY reason takes the
// first-release branch and emits releasable=true with exit 0.
@Suite("Release decision robustness")
struct ReleaseDecisionRobustnessTests {
    /// A git failure (here: not a git repository at all) must fail the guard,
    /// not claim the first release — non-zero exit and no `releasable=true` —
    /// so a transient git error under CI load can never cut a spurious
    /// release; stderr should surface the underlying git failure.
    /// Stated sensitivity: restore the silent conflation
    /// (`if last_tag="$(git describe ... 2>/dev/null)"` … else emit true) →
    /// a non-repo directory yields exit 0 plus releasable=true → both pins RED.
    @Test
    func gitFailureDoesNotClaimFirstRelease() throws {
        let emptyDir = FileManager.default.temporaryDirectory
            .appending(path: "slovo-reldec-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyDir) }

        let result = try ReleaseScriptRunner.run(
            "Scripts/release-decision.sh",
            environment: ["GITHUB_OUTPUT": ""],
            currentDirectory: emptyDir
        )
        #expect(result.exitCode != 0, Comment(rawValue: result.output))
        #expect(!result.output.contains("releasable=true"), Comment(rawValue: result.output))
    }

    /// The legitimate first-release branch stays intact: a real repo with
    /// commits but no `v*` tag yet is releasable (exit 0, releasable=true) —
    /// the robustness fix must not overshoot into failing genuine first
    /// releases.
    /// Stated sensitivity: make the fix treat a genuine no-tag repo as a git
    /// error (fail instead of emitting true) → RED. Born green on the current
    /// script — flagged for the independent mutation demonstration.
    @Test
    func noTagRepoIsFirstRelease() throws {
        let repo = try Self.makeUntaggedRepo(commits: ["feat: first feature"])
        defer { try? FileManager.default.removeItem(at: repo) }

        let result = try ReleaseScriptRunner.run(
            "Scripts/release-decision.sh",
            environment: ["GITHUB_OUTPUT": ""],
            currentDirectory: repo
        )
        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("releasable=true"), Comment(rawValue: result.output))
        #expect(!result.output.contains("releasable=false"), Comment(rawValue: result.output))
    }

    /// Untagged sibling of `ReleaseScriptRunner.makeTaggedRepo`, whose tag step
    /// is unconditional and whose git/commit helpers are private: init, config,
    /// then the given subjects as commits — deliberately no tag.
    private static func makeUntaggedRepo(commits subjects: [String]) throws -> URL {
        let repo = FileManager.default.temporaryDirectory
            .appending(path: "slovo-reldec-untagged-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"], in: repo)
        try git(["config", "user.email", "ci@example.com"], in: repo)
        try git(["config", "user.name", "CI"], in: repo)
        for subject in subjects {
            let marker = repo.appending(path: "log.txt")
            let previous = (try? String(contentsOf: marker, encoding: .utf8)) ?? ""
            try (previous + subject + "\n").write(to: marker, atomically: true, encoding: .utf8)
            try git(["add", "-A"], in: repo)
            try git(["commit", "-q", "-m", subject], in: repo)
        }
        return repo
    }

    private static func git(_ arguments: [String], in repo: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repo.path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FixtureError.gitFailed(arguments: arguments, output: String(decoding: data, as: UTF8.self))
        }
    }

    private enum FixtureError: Error {
        case gitFailed(arguments: [String], output: String)
    }
}
