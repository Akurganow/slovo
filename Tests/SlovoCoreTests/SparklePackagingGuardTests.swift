import Foundation
import Testing

// Packaging guard for the Sparkle auto-update engine (design spec:
// docs/superpowers/specs/2026-07-18-auto-update-design.md, "Packaging &
// signing"). Behavioral tokens and relative order are pinned — never exact
// command lines — so the implementation keeps latitude over paths and
// variables. It runs the signing script's dry run, as AppShellPackagingTests does.
@Suite("Sparkle packaging guards")
struct SparklePackagingGuardTests {
    /// The release `app` phase embeds Sparkle.framework into Contents/Frameworks
    /// (a symlink-preserving `ditto` copy — distinct from the zip's
    /// `ditto -c -k`), strips the XPC services the non-sandboxed app never
    /// uses, and signs inside-out: Autoupdate, then Updater.app, then the
    /// framework, then the app (the only codesign carrying slovo.entitlements).
    /// Stated sensitivity: missing embed or strip, a dropped nested sign, or
    /// the app signed before the framework → the ordered-needle check on the
    /// plan → RED.
    @Test
    func appPhaseEmbedsSparkleAndSignsInsideOut() throws {
        let appPlan = try Self.scriptPlan(["app"], appName: "DryRunSparkle-\(UUID().uuidString)", notary: true)
        #expect(appPlan.exitCode == 0, Comment(rawValue: appPlan.output))
        #expect(Self.output(appPlan.output, containsInOrder: [
            "DRY-RUN ditto", "Frameworks/Sparkle.framework",
            "XPCServices",
            "DRY-RUN codesign", "Autoupdate",
            "DRY-RUN codesign", "Updater.app",
            "DRY-RUN codesign", "Sparkle.framework",
            "DRY-RUN codesign", "slovo.entitlements",
        ]), Comment(rawValue: appPlan.output))
    }

    private static var packageRoot: URL {
        let testFile = URL(fileURLWithPath: "\(#filePath)")
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    // MARK: - DRY_RUN plan runner (copies of the AppShellPackagingTests helpers)

    private struct CommandResult {
        let exitCode: Int32
        let output: String
    }

    private static let scriptPath = packageRoot.appending(path: "Scripts/sign-and-notarize.sh").path

    /// DRY_RUN plan for a `sign-and-notarize.sh` phase; `appName`/`notary` add the
    /// optional `APP_NAME`/`NOTARY_PROFILE` environment overrides.
    private static func scriptPlan(
        _ arguments: [String],
        appName: String? = nil,
        notary: Bool = false
    ) throws -> CommandResult {
        var environment = ["DRY_RUN": "1", "SIGNING_IDENTITY": "Developer ID Application: Example (TEAMID)"]
        if let appName { environment["APP_NAME"] = appName }
        if notary { environment["NOTARY_PROFILE"] = "slovo-notary" }
        return try run("/bin/bash", arguments: [scriptPath] + arguments, environment: environment)
    }

    private static func run(
        _ executable: String,
        arguments: [String],
        environment: [String: String] = [:]
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(
            exitCode: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self)
        )
    }

    private static func output(_ output: String, containsInOrder needles: [String]) -> Bool {
        var searchStart = output.startIndex
        for needle in needles {
            guard let range = output.range(of: needle, range: searchStart..<output.endIndex) else {
                return false
            }
            searchStart = range.upperBound
        }
        return true
    }
}
