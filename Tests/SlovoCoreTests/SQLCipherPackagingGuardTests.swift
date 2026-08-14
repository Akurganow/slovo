import Foundation
import Testing

// Packaging guards for the SQLCipher dynamic framework (design spec:
// docs/superpowers/specs/2026-08-14-personalization-db-encryption-design.md,
// Decision 6). SQLCipher enters the dependency graph TRANSITIVELY (via the
// GRDB fork), so no manifest pin exists to scan — these guards watch the two
// packaging scripts, in the SparklePackagingGuardTests style.
@Suite("SQLCipher packaging guards")
struct SQLCipherPackagingGuardTests {
    /// The release `app` phase embeds SQLCipher.framework into
    /// Contents/Frameworks and signs it before the app codesign (the only one
    /// carrying slovo.entitlements) — an unembedded dynamic framework leaves
    /// the notarized app with a dangling @rpath load command that only
    /// resolves next to a development checkout. The copy SOURCE is pinned to
    /// the xcframework's macOS slice and the discovery function to a script
    /// read: a destination-only scan passes even when the ditto copies Sparkle
    /// under SQLCipher's name, and the printed plan alone cannot tell a real
    /// lookup from a hardcoded path.
    /// Stated sensitivity: drop the ditto or the framework codesign, sign the
    /// app first, or point the ditto at another framework → the ordered-needle
    /// scan → RED; delete or rename sqlcipher_framework_path → the discovery
    /// pin → RED.
    @Test
    func appPhaseEmbedsAndSignsSQLCipher() throws {
        let releaseScript = Self.strippingShellComments(from: try Self.source("Scripts/sign-and-notarize.sh"))
        let discovery = try #require(Self.shellFunctionBody(named: "sqlcipher_framework_path", in: releaseScript),
                                     "the release script must discover the framework, not hardcode a path")
        #expect(discovery.contains("SQLCipher.framework"), Comment(rawValue: discovery))

        let appPlan = try Self.scriptPlan(["app"], appName: "DryRunSQLCipher-\(UUID().uuidString)", notary: true)
        #expect(appPlan.exitCode == 0, Comment(rawValue: appPlan.output))
        #expect(Self.output(appPlan.output, containsInOrder: [
            "DRY-RUN ditto", "SQLCipher.xcframework/macos-", "Frameworks/SQLCipher.framework",
            "DRY-RUN codesign", "SQLCipher.framework",
            "DRY-RUN codesign", "slovo.entitlements",
        ]), Comment(rawValue: appPlan.output))
    }

    /// The dev launcher must stage and sign the same bundle shape as the
    /// release pipeline, or dev runs diverge from what ships. The staged copy
    /// is pinned to the discovery function's own variable, so a ditto reading
    /// another framework cannot satisfy it.
    /// Stated sensitivity: drop the embed from stage_bundle, copy a different
    /// source, drop the framework sign, or reorder it after the app → the
    /// body-scoped ordered scans → RED; delete or rename
    /// sqlcipher_framework_path → the discovery pin → RED.
    @Test
    func devLauncherStagesAndSignsSQLCipher() throws {
        let launcher = try Self.source("Scripts/build_and_run.sh")
        let script = Self.strippingShellComments(from: launcher)
        let discovery = try #require(Self.shellFunctionBody(named: "sqlcipher_framework_path", in: script),
                                     "the dev launcher must discover the framework, not hardcode a path")
        #expect(discovery.contains("SQLCipher.framework"), Comment(rawValue: discovery))

        let stage = try #require(Self.shellFunctionBody(named: "stage_bundle", in: script))
        #expect(Self.output(stage, containsInOrder: [
            "ditto", "\"$sqlcipher_framework\"", "Frameworks/SQLCipher.framework",
        ]), Comment(rawValue: stage))

        let sign = try #require(Self.shellFunctionBody(named: "sign_bundle", in: script))
        #expect(Self.output(sign, containsInOrder: [
            "codesign", "SQLCipher.framework",
            "codesign", "$APP_BUNDLE",
        ]), Comment(rawValue: sign))
    }

    // MARK: - Manifest scanning (copies of the PackageDependencyTests helpers)

    private static var packageRoot: URL {
        let testFile = URL(fileURLWithPath: "\(#filePath)")
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func source(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot.appending(path: relativePath), encoding: .utf8)
    }

    // MARK: - Shell scanning (copies of the PackageDependencyTests helpers)

    private static func strippingShellComments(from source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { strippingHashComment(from: String($0)) }
            .joined(separator: "\n")
    }

    private static func strippingHashComment(from line: String) -> String {
        var output = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaped = false

        for character in line {
            if escaped {
                output.append(character)
                escaped = false
            } else if character == "\\" && !inSingleQuote {
                output.append(character)
                escaped = true
            } else if character == "'" && !inDoubleQuote {
                output.append(character)
                inSingleQuote.toggle()
            } else if character == "\"" && !inSingleQuote {
                output.append(character)
                inDoubleQuote.toggle()
            } else if character == "#" && !inSingleQuote && !inDoubleQuote {
                break
            } else {
                output.append(character)
            }
        }
        return output
    }

    private static func shellFunctionBody(named name: String, in source: String) -> String? {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "\(name)() {"
        }) else {
            return nil
        }
        guard let end = lines[(start + 1)...].firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "}"
        }) else {
            return nil
        }
        return lines[start...end].joined(separator: "\n")
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
