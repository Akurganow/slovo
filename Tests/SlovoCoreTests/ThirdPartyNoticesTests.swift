import Foundation
import Testing

// License-compliance guard for the third-party components Slovo redistributes in
// its app bundle: the packaging scripts install the top-level THIRD-PARTY-NOTICES.md
// artifact into Contents/Resources before the bundle is signed so the notices travel
// with the binary. It runs the signing script's dry run, as AppShellPackagingTests does.
@Suite("Third-party notices")
struct ThirdPartyNoticesTests {
    /// The release `app` phase must install the notices artifact into
    /// Contents/Resources, and it must do so BEFORE the app bundle is sealed by
    /// codesign — a resource added after signing would break the seal.
    /// Stated sensitivity: drop the install step → the dest path is absent → RED;
    /// move the install after the app codesign → the ordered-needle scan (notices
    /// install before the slovo.entitlements codesign) → RED.
    @Test
    func releaseAppPhaseInstallsNoticesIntoResourcesBeforeSigning() throws {
        let appPlan = try Self.scriptPlan(["app"], appName: "DryRunNotices-\(UUID().uuidString)", notary: true)
        #expect(appPlan.exitCode == 0, Comment(rawValue: appPlan.output))
        #expect(appPlan.output.contains("Resources/THIRD-PARTY-NOTICES.md"), Comment(rawValue: appPlan.output))
        // The app codesign is the only one carrying slovo.entitlements; the notices
        // install must precede it.
        #expect(Self.output(appPlan.output, containsInOrder: [
            "Resources/THIRD-PARTY-NOTICES.md", "DRY-RUN codesign", "slovo.entitlements",
        ]), Comment(rawValue: appPlan.output))
    }

    // MARK: - Helpers (copies of the AppShellPackagingTests helpers)

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

    private static var packageRoot: URL {
        let testFile = URL(fileURLWithPath: "\(#filePath)")
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
