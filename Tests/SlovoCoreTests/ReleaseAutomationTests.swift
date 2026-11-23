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
