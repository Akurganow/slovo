import Foundation
import Testing

// Dry-run checks of the packaging scripts. Real launch, glyph rendering, signing,
// notarization, and TCC persistence are verified live.
@Suite("App shell and packaging artifacts")
struct AppShellPackagingTests {
    /// The shared bundle steps must stage the SlovoCore resource bundle into
    /// Contents/Resources.
    /// Stated sensitivity: deleting the `ditto … slovo_SlovoCore.bundle`
    /// staging line goes RED here — a missing bundle otherwise ships silently as
    /// example-free prompts.
    @Test
    func packagingScriptsStageThePromptExamplesBundle() throws {
        let appPlan = try Self.scriptPlan(["app"], appName: "DryRunPrompts-\(UUID().uuidString)")

        #expect(appPlan.output.split(separator: "\n").contains {
            $0.hasPrefix("DRY-RUN ditto ") && $0.hasSuffix("/Contents/Resources/slovo_SlovoCore.bundle")
        }, Comment(rawValue: appPlan.output))
    }

    @Test
    func signingScriptPlansTheAppAndDmgPhasesAndRejectsBadNames() throws {
        // `app` phase: build + sign + notarize the bundle. Stapling is the sole
        // manual step, so the phase never runs `stapler`; DMG packaging is separate.
        let appPlan = try Self.scriptPlan(["app"], appName: "DryRunTestBundle-\(UUID().uuidString)", notary: true)
        #expect(appPlan.exitCode == 0, Comment(rawValue: appPlan.output))
        #expect(appPlan.output.contains("--disable-automatic-resolution"), Comment(rawValue: appPlan.output))
        #expect(Self.output(appPlan.output, containsInOrder: [
            "DRY-RUN swift build", "DRY-RUN install -d", "DRY-RUN install",
            "DRY-RUN xcrun actool", "DRY-RUN codesign", "DRY-RUN ditto -c -k --keepParent",
            "DRY-RUN xcrun notarytool",
        ]), Comment(rawValue: appPlan.output))
        #expect(!appPlan.output.contains("DRY-RUN hdiutil"), Comment(rawValue: appPlan.output))
        #expect(!appPlan.output.contains("DRY-RUN xcrun stapler"), Comment(rawValue: appPlan.output))

        // `dmg` phase: package the already-stapled app into a signed, notarized DMG.
        let dmgName = "DryRunDmgBundle-\(UUID().uuidString)"
        let dmgAppPath = Self.packageRoot.appending(path: ".build/dist/\(dmgName).app")
        try FileManager.default.createDirectory(at: dmgAppPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dmgAppPath) }
        let dmgPlan = try Self.scriptPlan(["dmg"], appName: dmgName, notary: true)
        #expect(dmgPlan.exitCode == 0, Comment(rawValue: dmgPlan.output))
        #expect(Self.output(dmgPlan.output, containsInOrder: [
            "DRY-RUN ditto", "DRY-RUN hdiutil create", "DRY-RUN codesign", "DRY-RUN xcrun notarytool",
        ]), Comment(rawValue: dmgPlan.output))
        #expect(!dmgPlan.output.contains("DRY-RUN xcrun stapler"), Comment(rawValue: dmgPlan.output))

        // A missing phase is a usage error.
        let noPhase = try Self.scriptPlan([])
        #expect(noPhase.exitCode == 64, Comment(rawValue: noPhase.output))

        // Each half of the name guard's `*/*|*..*` pattern rejects `../../bad` alone,
        // so `a/b` and `a..b` are what tell the halves apart.
        for badName in ["../../bad", "a/b", "a..b"] {
            let invalidName = try Self.scriptPlan(["app"], appName: badName)
            #expect(invalidName.exitCode == 64, Comment(rawValue: "\(badName): \(invalidName.output)"))
            #expect(!invalidName.output.contains("DRY-RUN codesign"), Comment(rawValue: badName))
        }

        let existingName = "ExistingTestBundle"
        let existingPath = Self.packageRoot.appending(path: ".build/dist/\(existingName).app")
        try FileManager.default.createDirectory(at: existingPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: existingPath) }
        let staleBundle = try Self.scriptPlan(["app"], appName: existingName)
        #expect(staleBundle.exitCode == 65, Comment(rawValue: staleBundle.output))
        #expect(!staleBundle.output.contains("DRY-RUN codesign"))
    }

    private struct CommandResult {
        let exitCode: Int32
        let output: String
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
