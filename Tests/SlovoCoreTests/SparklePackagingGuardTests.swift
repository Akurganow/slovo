import Foundation
import Testing

// Packaging guards for the Sparkle auto-update engine (design spec:
// docs/superpowers/specs/2026-07-18-auto-update-design.md, "Packaging &
// signing"). Behavioral tokens and relative order are pinned — never exact
// command lines — so the implementation keeps latitude over paths and
// variables. A focused suite with private helper copies, per the house
// precedent set by PackageDependencyTests and AppShellPackagingTests.
@Suite("Sparkle packaging guards")
struct SparklePackagingGuardTests {
    /// Sparkle powers auto-update from the app shell ONLY: the manifest depends
    /// on sparkle-project/Sparkle, the `slovo` executable links the product, and
    /// `SlovoCore` stays Sparkle-free — the SwiftPM target graph, not a source
    /// scan, is what makes `import Sparkle` inside the core uncompilable. The
    /// app target also needs the rpath so the embedded framework resolves at
    /// launch.
    /// Stated sensitivity: drop the dependency, the product link, or the
    /// `@executable_path/../Frameworks` rpath → RED; move the rpath flag to
    /// another target → the block-scoped pin → RED; link Sparkle into a second
    /// target (e.g. SlovoCore) → the single-occurrence and core-free pins → RED.
    @Test
    func sparkleIsLinkedIntoAppTargetOnly() throws {
        let source = try String(contentsOfFile: Self.packagePath, encoding: .utf8)
        let code = Self.strippingComments(from: source)
        let appTarget = try #require(Self.executableTargetBlock(named: "slovo", in: code))
        let coreTarget = try #require(Self.targetBlock(named: "SlovoCore", in: code))

        #expect(code.contains("sparkle-project/Sparkle"))
        #expect(appTarget.contains(".product(name: \"Sparkle\""))
        #expect(!coreTarget.contains("Sparkle"), "SlovoCore must stay Sparkle-free; the target graph enforces core purity")
        #expect(Self.occurrences(of: ".product(name: \"Sparkle\"", in: code) == 1,
                "exactly one target may link the Sparkle product")
        #expect(appTarget.contains("@executable_path/../Frameworks"),
                "the slovo target needs the Frameworks rpath so the embedded Sparkle.framework resolves at launch")
    }

    /// The release `app` phase embeds Sparkle.framework into Contents/Frameworks
    /// (a symlink-preserving `ditto` copy — distinct from the zip's
    /// `ditto -c -k`), strips the XPC services the non-sandboxed app never
    /// uses, and signs inside-out: Autoupdate, then Updater.app, then the
    /// framework, then the app (the only codesign carrying slovo.entitlements).
    /// Deep SIGNING mis-signs Sparkle's helpers and fails only at notarization
    /// (Sparkle #1641), so `--deep` must stay verification-only in both
    /// packaging scripts — that pin is a tripwire, vacuously green until a
    /// `--deep` enters either script.
    /// Stated sensitivity: missing embed or strip, a dropped nested sign, or
    /// the app signed before the framework → the ordered-needle scan → RED;
    /// add `codesign --deep --sign` to either script → RED.
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

        for script in ["Scripts/sign-and-notarize.sh", "Scripts/build_and_run.sh"] {
            let lines = try Self.source(script).split(separator: "\n")
            for line in lines where line.contains("--deep") {
                #expect(line.contains("--verify"), "--deep is verification-only in \(script): \(line)")
            }
        }
    }

    /// The dev launcher must stage and sign the same bundle shape as the
    /// release pipeline, or dev runs diverge from what ships: `stage_bundle`
    /// embeds Sparkle.framework with a symlink-preserving `ditto` and strips
    /// the unused XPC services; `sign_bundle` signs inside-out and ends at the
    /// app bundle.
    /// Stated sensitivity: drop the embed or strip from staging, drop a nested
    /// sign, or reorder signing (app before framework) → the body-scoped
    /// ordered scans → RED.
    @Test
    func devLauncherStagesAndSignsSparkleInsideOut() throws {
        let launcher = try Self.source("Scripts/build_and_run.sh")
        let script = Self.strippingShellComments(from: launcher)

        let stage = try #require(Self.shellFunctionBody(named: "stage_bundle", in: script))
        #expect(Self.output(stage, containsInOrder: ["ditto", "Frameworks/Sparkle.framework"]), Comment(rawValue: stage))
        #expect(stage.contains("XPCServices"), "staging must strip the unused Sparkle XPC services")

        let sign = try #require(Self.shellFunctionBody(named: "sign_bundle", in: script))
        #expect(Self.output(sign, containsInOrder: [
            "codesign", "Autoupdate",
            "codesign", "Updater.app",
            "codesign", "Sparkle.framework",
            "codesign", "$APP_BUNDLE",
        ]), Comment(rawValue: sign))
    }

    /// Sparkle's whole silent-update contract is declared in Info.plist: the
    /// appcast feed, the EdDSA pin, automatic check+install, the hourly cadence
    /// (Sparkle's documented and code-enforced minimum), and
    /// verify-before-extraction. The EdDSA key is pinned to its EXACT value on
    /// purpose: an accidental key swap would silently orphan every existing
    /// install (their Sparkle would reject all future signatures) — key
    /// rotation is a deliberate event that updates this pin consciously, never
    /// a side effect.
    /// Stated sensitivity: drop or typo any SU key, loosen the interval, or
    /// swap the feed/EdDSA value → the matching equality pin → RED.
    @Test
    func infoPlistCarriesTheSparkleAutoUpdateContract() throws {
        let data = try Data(contentsOf: Self.packageRoot.appending(path: "Resources/Info.plist"))
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        #expect(plist["SUFeedURL"] as? String == "https://github.com/Akurganow/slovo/releases/latest/download/appcast.xml")
        #expect(plist["SUPublicEDKey"] as? String == "Dj1g2DArdtH4NFiJMtqSAiFgnc1UIJieDaziw5cSOXo=")
        #expect(plist["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(plist["SUAutomaticallyUpdate"] as? Bool == true)
        #expect(plist["SUScheduledCheckInterval"] as? Int == 3_600)
        #expect(plist["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
    }

    // MARK: - Manifest scanning (copies of the PackageDependencyTests helpers)

    private static var packagePath: String {
        packageRoot.appending(path: "Package.swift").path
    }

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

    private static func targetBlock(named name: String, in source: String) -> String? {
        let needle = ".target(\n            name: \"\(name)\""
        guard let range = source.range(of: needle) else { return nil }
        return parenthesizedBlock(startingAt: range.lowerBound, in: source)
    }

    private static func executableTargetBlock(named name: String, in source: String) -> String? {
        let needle = ".executableTarget(\n            name: \"\(name)\""
        guard let range = source.range(of: needle) else { return nil }
        return parenthesizedBlock(startingAt: range.lowerBound, in: source)
    }

    private static func parenthesizedBlock(startingAt start: String.Index, in source: String) -> String? {
        var depth = 0
        var started = false
        var index = start
        while index < source.endIndex {
            let character = source[index]
            if character == "(" {
                depth += 1
                started = true
            } else if character == ")" {
                depth -= 1
                if started && depth == 0 {
                    return String(source[start...index])
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        var count = 0
        var searchStart = haystack.startIndex
        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    private static func strippingComments(from source: String) -> String {
        var output = ""
        var index = source.startIndex
        var inLineComment = false
        var inBlockComment = false
        var inString = false

        while index < source.endIndex {
            let character = source[index]
            let nextIndex = source.index(after: index)
            let next = nextIndex < source.endIndex ? source[nextIndex] : "\0"

            if inLineComment {
                if character == "\n" {
                    inLineComment = false
                    output.append(character)
                }
            } else if inBlockComment {
                if character == "*" && next == "/" {
                    inBlockComment = false
                    index = nextIndex
                }
            } else if inString {
                output.append(character)
                if character == "\"" {
                    inString = false
                }
            } else if character == "/" && next == "/" {
                inLineComment = true
                index = nextIndex
            } else if character == "/" && next == "*" {
                inBlockComment = true
                index = nextIndex
            } else {
                output.append(character)
                if character == "\"" {
                    inString = true
                }
            }
            index = source.index(after: index)
        }
        return output
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
