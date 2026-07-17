import Foundation
import Testing

// Static CI checks for the release-automation helper scripts that the Release
// workflow drives on GitHub runners: the release-decision guard, the Info.plist
// version stamp, and the Keep a Changelog promotion. All run hermetically against
// temp fixtures — no real git remote, signing, network, or Apple credentials.

@Suite("Release decision guard")
struct ReleaseDecisionGuardTests {
    @Test
    func featWarrantsRelease() throws {
        // Sensitivity: drop the feat|fix|perf header branch and this goes RED.
        try expectDecision(true, for: ["feat: add mute switch"])
    }

    @Test
    func fixWarrantsRelease() throws {
        // Sensitivity: same header branch removal drops fixes from the release set.
        try expectDecision(true, for: ["fix(asr): reject impossible suffix"])
    }

    @Test
    func perfWarrantsRelease() throws {
        // Sensitivity: removing `perf` from the type alternation makes this RED.
        try expectDecision(true, for: ["perf: warm the model earlier"])
    }

    @Test
    func scopedFeatWarrantsRelease() throws {
        // Sensitivity: a header pattern without the optional `(scope)` group misses
        // `feat(ui):` and this goes RED.
        try expectDecision(true, for: ["feat(ui): add menu-bar switch"])
    }

    @Test
    func breakingBangWarrantsRelease() throws {
        // A `type!:` header is a breaking change regardless of type.
        // Sensitivity: drop the `!` header branch and a breaking refactor is skipped.
        try expectDecision(true, for: ["refactor(core)!: drop macOS 25 support"])
    }

    @Test
    func breakingFooterWarrantsRelease() throws {
        // Sensitivity: remove the `BREAKING CHANGE:` footer grep and a body-only
        // breaking change is missed, so this goes RED.
        try expectDecision(true, for: ["refactor: rework engine\n\nBREAKING CHANGE: config format changed"])
    }

    @Test
    func nonReleasableTypesDoNotWarrantRelease() throws {
        // The core false-green guard: a push of only non-release types must NOT cut a
        // release, even though release-it's conventional-changelog engine would still
        // recommend a patch for a non-empty commit set.
        // Sensitivity: classify any non-feat/fix/perf/breaking commit as releasable and
        // this goes RED.
        try expectDecision(false, for: [
            "docs: tidy readme",
            "chore: bump deps",
            "ci: cache spm",
            "build: adjust flags",
            "style: reformat",
            "test: add coverage",
            "refactor: rename symbol",
        ])
    }

    @Test
    func emptyCommitSetDoesNotWarrantRelease() throws {
        // Sensitivity: a guard that defaults to releasable on empty input goes RED here.
        try expectDecision(false, for: [])
    }

    @Test
    func anyReleasableInMixedSetWarrantsRelease() throws {
        // Sensitivity: a guard that only inspects the first (or last) commit misses the
        // buried feat and goes RED.
        try expectDecision(true, for: ["docs: note change", "feat: real feature", "chore: cleanup"])
    }

    @Test
    func releaseBookkeepingCommitIsInert() throws {
        // The publish job's own `chore(release): vX [skip ci]` commit plus a merge must
        // never, by themselves, re-trigger a release. This pins the loop-safety property.
        // Sensitivity: counting `chore(release)` as releasable makes this RED.
        try expectDecision(false, for: [
            "Merge pull request #6 from fork/topic",
            "chore(release): v0.9.0 [skip ci]",
        ])
    }

    @Test
    func writesDecisionToGithubOutputFile() throws {
        // The workflow's downstream `if:` gate reads `releasable` from $GITHUB_OUTPUT,
        // not stdout — that append branch is the actual CI wire and every other test
        // disables it (GITHUB_OUTPUT="").
        // Sensitivity: drop the `>> "$GITHUB_OUTPUT"` append in emit() and this goes RED.
        let outputFile = FileManager.default.temporaryDirectory
            .appending(path: "gha-output-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: outputFile.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outputFile) }
        let result = try ReleaseScriptRunner.run(
            "Scripts/release-decision.sh",
            environment: ["RELEASE_DECISION_INPUT": "stdin", "GITHUB_OUTPUT": outputFile.path],
            standardInput: "feat: real feature\u{0}"
        )
        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        let written = try String(contentsOf: outputFile, encoding: .utf8)
        #expect(written.contains("releasable=true"), Comment(rawValue: written))
    }

    private func expectDecision(_ releasable: Bool, for commits: [String]) throws {
        let result = try ReleaseScriptRunner.run(
            "Scripts/release-decision.sh",
            environment: ["RELEASE_DECISION_INPUT": "stdin", "GITHUB_OUTPUT": ""],
            standardInput: commits.map { $0 + "\u{0}" }.joined()
        )
        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        let expected = "releasable=\(releasable)"
        let opposite = "releasable=\(!releasable)"
        #expect(result.output.contains(expected), Comment(rawValue: result.output))
        #expect(!result.output.contains(opposite), Comment(rawValue: result.output))
    }
}

@Suite("Release decision guard over real git history")
struct ReleaseDecisionGitModeTests {
    @Test
    func featAfterLastTagWarrantsRelease() throws {
        let repo = try ReleaseScriptRunner.makeTaggedRepo(afterTag: ["feat: add capability"])
        defer { try? FileManager.default.removeItem(atPath: repo.path) }
        let result = try ReleaseScriptRunner.run(
            "Scripts/release-decision.sh",
            environment: ["GITHUB_OUTPUT": ""],
            currentDirectory: repo
        )
        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("releasable=true"), Comment(rawValue: result.output))
    }

    @Test
    func docsOnlyAfterLastTagDoesNotWarrantRelease() throws {
        // Production-faithful: proves the range is `<last v* tag>..HEAD`, not all history.
        // Sensitivity: scanning the whole history (which contains a pre-tag feat) would
        // wrongly report releasable=true, turning this RED.
        let repo = try ReleaseScriptRunner.makeTaggedRepo(afterTag: ["docs: clarify usage"])
        defer { try? FileManager.default.removeItem(atPath: repo.path) }
        let result = try ReleaseScriptRunner.run(
            "Scripts/release-decision.sh",
            environment: ["GITHUB_OUTPUT": ""],
            currentDirectory: repo
        )
        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("releasable=false"), Comment(rawValue: result.output))
    }
}

@Suite("App version stamp")
struct AppVersionStampTests {
    @Test
    func stampsBothVersionKeys() throws {
        let plist = try ReleaseScriptRunner.copyOfFixture("Resources/Info.plist")
        defer { try? FileManager.default.removeItem(atPath: plist) }
        let result = try ReleaseScriptRunner.run(
            "Scripts/stamp-app-version.sh",
            arguments: ["0.10.0", "42", plist]
        )
        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        // Sensitivity: skip either PlistBuddy Set and the matching read-back goes RED.
        #expect(try ReleaseScriptRunner.plistValue(":CFBundleShortVersionString", in: plist) == "0.10.0")
        #expect(try ReleaseScriptRunner.plistValue(":CFBundleVersion", in: plist) == "42")
    }

    @Test
    func acceptsMarkedDevShortVersion() throws {
        // The non-release trunk build stamps a marked short version so it never
        // masquerades as a released build.
        let plist = try ReleaseScriptRunner.copyOfFixture("Resources/Info.plist")
        defer { try? FileManager.default.removeItem(atPath: plist) }
        let result = try ReleaseScriptRunner.run(
            "Scripts/stamp-app-version.sh",
            arguments: ["0.9.0-ci.777", "777", plist]
        )
        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(try ReleaseScriptRunner.plistValue(":CFBundleShortVersionString", in: plist) == "0.9.0-ci.777")
    }

    @Test
    func rejectsNonIntegerBundleVersion() throws {
        // Sensitivity: remove the integer guard and this exits 0 instead of 64.
        let plist = try ReleaseScriptRunner.copyOfFixture("Resources/Info.plist")
        defer { try? FileManager.default.removeItem(atPath: plist) }
        let result = try ReleaseScriptRunner.run(
            "Scripts/stamp-app-version.sh",
            arguments: ["0.10.0", "not-an-int", plist]
        )
        #expect(result.exitCode == 64, Comment(rawValue: result.output))
    }

    @Test
    func rejectsMissingArguments() throws {
        let result = try ReleaseScriptRunner.run("Scripts/stamp-app-version.sh", arguments: ["0.10.0"])
        #expect(result.exitCode == 64, Comment(rawValue: result.output))
    }
}

@Suite("Changelog promotion")
struct ChangelogPromotionTests {
    @Test
    func promotesUnreleasedIntoDatedVersion() throws {
        let changelog = try ReleaseScriptRunner.copyOfFixture("CHANGELOG.md")
        defer { try? FileManager.default.removeItem(atPath: changelog) }
        let result = try ReleaseScriptRunner.run(
            "Scripts/promote-changelog.sh",
            arguments: ["0.10.0", "2026-07-17", changelog]
        )
        #expect(result.exitCode == 0, Comment(rawValue: result.output))

        let contents = try String(contentsOfFile: changelog, encoding: .utf8)
        // Sensitivity: dropping the inserted version header, or losing the fresh
        // Unreleased header, breaks this ordered match.
        #expect(ReleaseScriptRunner.appears(
            ["## [Unreleased]", "## [0.10.0] - 2026-07-17", "## [0.9.0] - 2026-07-14"],
            inOrderWithin: contents
        ), Comment(rawValue: contents))
        let headerLines = contents.split(separator: "\n").filter { $0 == "## [Unreleased]" }
        #expect(headerLines.count == 1, "expected exactly one Unreleased header")
    }

    @Test
    func failsWhenNoUnreleasedSection() throws {
        // Sensitivity: remove the pre-check and awk silently no-ops (exit 0) instead of 65.
        let path = FileManager.default.temporaryDirectory
            .appending(path: "changelog-\(UUID().uuidString).md").path
        try "# Changelog\n\n## [0.9.0] - 2026-07-14\n".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let result = try ReleaseScriptRunner.run(
            "Scripts/promote-changelog.sh",
            arguments: ["0.10.0", "2026-07-17", path]
        )
        #expect(result.exitCode == 65, Comment(rawValue: result.output))
    }
}

enum ReleaseScriptRunner {
    struct CommandResult {
        let exitCode: Int32
        let output: String
    }

    /// Runs a repo script under `/bin/bash`, capturing stdout+stderr through a
    /// per-invocation file the child owns. A regular-file target (never a parent Pipe)
    /// cannot be inherited by a concurrently spawned child and mix streams, so captures
    /// stay isolated under the parallel test runner.
    static func run(
        _ relativeScript: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        standardInput: String? = nil,
        currentDirectory: URL? = nil
    ) throws -> CommandResult {
        let scriptPath = packageRoot.appending(path: relativeScript).path
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "release-script-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.standardOutput = outputHandle
        process.standardError = outputHandle
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }

        var inputURL: URL?
        if let standardInput {
            let url = FileManager.default.temporaryDirectory
                .appending(path: "release-script-stdin-\(UUID().uuidString)")
            try Data(standardInput.utf8).write(to: url)
            inputURL = url
            process.standardInput = try FileHandle(forReadingFrom: url)
        }
        defer { if let inputURL { try? FileManager.default.removeItem(at: inputURL) } }

        try process.run()
        process.waitUntilExit()
        let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        return CommandResult(exitCode: process.terminationStatus, output: output)
    }

    /// Isolated git repo with a `v9.9.0` tag on a pre-existing feat, then the given
    /// commit subjects layered on HEAD. The pre-tag feat is the decoy that a
    /// whole-history scan would wrongly count.
    static func makeTaggedRepo(afterTag commitSubjects: [String]) throws -> URL {
        let repo = FileManager.default.temporaryDirectory.appending(path: "slovo-reldec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        _ = try git(["init", "-q", "-b", "main"], in: repo)
        _ = try git(["config", "user.email", "ci@example.com"], in: repo)
        _ = try git(["config", "user.name", "CI"], in: repo)
        try commit("feat: pre-tag feature that must not leak past the tag", in: repo)
        _ = try git(["tag", "v9.9.0"], in: repo)
        for subject in commitSubjects {
            try commit(subject, in: repo)
        }
        return repo
    }

    static func copyOfFixture(_ relativePath: String) throws -> String {
        let source = packageRoot.appending(path: relativePath)
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "release-fixture-\(UUID().uuidString)-\(source.lastPathComponent)")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination.path
    }

    static func plistValue(_ entry: String, in path: String) throws -> String {
        let result = try runTool("/usr/libexec/PlistBuddy", ["-c", "Print \(entry)", path])
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func appears(_ needles: [String], inOrderWithin haystack: String) -> Bool {
        var searchStart = haystack.startIndex
        for needle in needles {
            guard let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) else {
                return false
            }
            searchStart = range.upperBound
        }
        return true
    }

    private static func commit(_ subject: String, in repo: URL) throws {
        let marker = repo.appending(path: "log.txt")
        let previous = (try? String(contentsOf: marker, encoding: .utf8)) ?? ""
        try (previous + subject + "\n").write(to: marker, atomically: true, encoding: .utf8)
        _ = try git(["add", "-A"], in: repo)
        _ = try git(["commit", "-q", "-m", subject], in: repo)
    }

    private static func git(_ arguments: [String], in repo: URL) throws -> CommandResult {
        try runTool("/usr/bin/git", ["-C", repo.path] + arguments)
    }

    private static func runTool(_ launchPath: String, _ arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(
            exitCode: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self)
        )
    }

    static var packageRoot: URL {
        URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
