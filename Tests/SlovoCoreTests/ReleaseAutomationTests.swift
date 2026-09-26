import Foundation
import Testing

// Static CI checks for the release-automation helper script that the Release
// workflow drives on GitHub runners: the Info.plist version stamp. It runs
// hermetically against a temp fixture — no real git remote, signing, network,
// or Apple credentials.

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

@Suite("Changelog header")
struct ChangelogHeaderTests {
    /// The publish job's `git-cliff --prepend` strips `[changelog] header` from
    /// CHANGELOG.md by exact text before writing the new section under it. A header
    /// edited in one file and not the other is not an error to git-cliff: the next
    /// release writes the header a second time, mid-file, and exits 0.
    /// Stated sensitivity: change one word of the header in either file → RED.
    @Test
    func changelogStartsWithTheHeaderGitCliffStrips() throws {
        let config = try String(
            contentsOf: ReleaseScriptRunner.packageRoot.appending(path: "cliff.toml"),
            encoding: .utf8
        )
        let opening = "header = \"\"\"\n"
        let start = try #require(config.range(of: opening), "cliff.toml must declare [changelog] header")
        let end = try #require(
            config.range(of: "\"\"\"", range: start.upperBound..<config.endIndex),
            "cliff.toml header must close its triple quotes"
        )
        let header = String(config[start.upperBound..<end.lowerBound])

        let changelog = try String(
            contentsOf: ReleaseScriptRunner.packageRoot.appending(path: "CHANGELOG.md"),
            encoding: .utf8
        )
        #expect(!header.isEmpty)
        #expect(changelog.hasPrefix(header), Comment(rawValue: header))
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
