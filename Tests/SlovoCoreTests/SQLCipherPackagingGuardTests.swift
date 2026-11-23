import Foundation
import Testing

// Packaging guard for the SQLCipher dynamic framework (design spec:
// docs/superpowers/specs/2026-08-14-personalization-db-encryption-design.md,
// Decision 6). SQLCipher enters the dependency graph TRANSITIVELY (via the
// GRDB fork), so no manifest pin exists to scan — the guard runs the packaging
// script's dry run and reads the plan it prints.
@Suite("SQLCipher packaging guards")
struct SQLCipherPackagingGuardTests {
    /// The release `app` phase embeds SQLCipher.framework into
    /// Contents/Frameworks, through the bundle steps the dev launcher shares,
    /// and signs it before the app codesign (the only one
    /// carrying slovo.entitlements) — an unembedded dynamic framework leaves
    /// the notarized app with a dangling @rpath load command that only
    /// resolves next to a development checkout. The copy SOURCE is pinned to
    /// the xcframework's macOS slice: a destination-only check passes even when
    /// the ditto copies Sparkle under SQLCipher's name.
    /// Stated sensitivity: drop the ditto or the framework codesign, sign the
    /// app first, or point the ditto at another framework → the ordered-needle
    /// check on the plan → RED.
    @Test
    func appPhaseEmbedsAndSignsSQLCipher() throws {
        let appPlan = try Self.scriptPlan(["app"], appName: "DryRunSQLCipher-\(UUID().uuidString)", notary: true)
        #expect(appPlan.exitCode == 0, Comment(rawValue: appPlan.output))
        #expect(Self.output(appPlan.output, containsInOrder: [
            "DRY-RUN ditto", "SQLCipher.xcframework/macos-", "Frameworks/SQLCipher.framework",
            "DRY-RUN codesign", "SQLCipher.framework",
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
