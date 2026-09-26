import Foundation
import Testing

// Static CI checks for the release-automation helper scripts that the Release
// workflow drives on GitHub runners: the Info.plist version stamp and the Keep a
// Changelog promotion. All run hermetically against temp fixtures — no real git
// remote, signing, network, or Apple credentials.

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

@Suite("Release workflow platform contract")
struct ReleaseWorkflowPlatformTests {
    /// The publish job commits the version through the repo's single stamping
    /// script, which uses Apple userland (PlistBuddy, plutil) — a Linux runner has
    /// neither and dies with exit 127, which is exactly how the first live release
    /// run failed.
    /// Stated sensitivity: move `publish` back to `runs-on: ubuntu-latest` (or any
    /// non-macOS runner) → RED.
    @Test
    func publishJobRunsOnMacosForTheVersionStamp() throws {
        let workflowPath = ReleaseScriptRunner.packageRoot
            .appending(path: ".github/workflows/release.yml")
        let workflow = try String(contentsOf: workflowPath, encoding: .utf8)
        let publishJob = try #require(
            workflow.range(of: "\n  publish:").map { workflow[$0.lowerBound...] },
            "release.yml must declare a publish job"
        )

        #expect(publishJob.contains("runs-on: macos-"))
        #expect(!publishJob.contains("runs-on: ubuntu"))
    }
}

// The About header version line distinguishes dev from release builds via the
// `SlovoDevBuild` Info.plist key. The guarantee that a shipped artifact can never
// carry it is structural — the key has exactly one write site, the dev launcher
// stamping the STAGED bundle copy — and this suite pins that structure on all
// three sides.
@Suite("Dev-build marker guard")
struct DevBuildMarkerGuardTests {
    /// Both CI packaging paths install the committed Resources/Info.plist verbatim,
    /// so the marker key must never be committed there.
    /// Stated sensitivity: add a `SlovoDevBuild` entry to Resources/Info.plist → RED.
    @Test
    func committedPlistCarriesNoDevMarker() throws {
        let plist = try String(
            contentsOf: ReleaseScriptRunner.packageRoot.appending(path: "Resources/Info.plist"),
            encoding: .utf8
        )
        #expect(!plist.contains("SlovoDevBuild"))
    }

    /// The dev launcher stamps the marker into the staged plist copy (before
    /// signing, so the signature seals it) — the only write site of the key.
    /// Stated sensitivity: drop the stamp line, typo the key, or retarget it at the
    /// committed plist → RED (the exact-line match breaks).
    @Test
    func devLauncherStampsTheMarkerIntoTheStagedPlist() throws {
        let launcher = try String(
            contentsOf: ReleaseScriptRunner.packageRoot.appending(path: "Scripts/build_and_run.sh"),
            encoding: .utf8
        )
        #expect(launcher.contains(
            #"/usr/libexec/PlistBuddy -c "Add :SlovoDevBuild bool true" "$APP_CONTENTS/Info.plist""#
        ))
    }

    /// The release path must never learn the key: the packaging script and the
    /// release workflow are the only ways a shipped artifact is produced.
    /// Stated sensitivity: mention `SlovoDevBuild` in either file → RED.
    @Test
    func releasePackagingNeverMentionsTheDevMarker() throws {
        for path in ["Scripts/sign-and-notarize.sh", ".github/workflows/release.yml"] {
            let contents = try String(
                contentsOf: ReleaseScriptRunner.packageRoot.appending(path: path),
                encoding: .utf8
            )
            #expect(!contents.contains("SlovoDevBuild"), Comment(rawValue: path))
        }
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
    static func run(_ relativeScript: String, arguments: [String] = []) throws -> CommandResult {
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
        process.standardOutput = outputHandle
        process.standardError = outputHandle

        try process.run()
        process.waitUntilExit()
        let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        return CommandResult(exitCode: process.terminationStatus, output: output)
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
