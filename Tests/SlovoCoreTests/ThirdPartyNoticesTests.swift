import Foundation
import Testing

// License-compliance guards for the third-party components Slovo redistributes in
// its app bundle. Two planes are pinned: the top-level THIRD-PARTY-NOTICES.md
// artifact reproduces every bundled component's copyright + permission notice, and
// the packaging scripts install that artifact into Contents/Resources before the
// bundle is signed so the notices travel with the binary. A focused suite with
// private helper copies, per the house precedent set by AppShellPackagingTests and
// SparklePackagingGuardTests.
@Suite("Third-party notices")
struct ThirdPartyNoticesTests {
    /// The notices artifact must credit EVERY component the shipped bundle links,
    /// each by a distinctive copyright line that only its verbatim notice carries,
    /// plus the top-level project copyright. Settings and LaunchAtLogin share an
    /// identical MIT body, so their independent presence is pinned by their section
    /// headers and source URLs rather than the (shared) copyright line.
    /// Stated sensitivity: delete any component's block (or its Sparkle sub-notice)
    /// → its distinctive copyright line vanishes → the matching `#expect` goes RED.
    /// RED today: the file does not yet exist, so every assertion fails.
    @Test
    func noticesFileReproducesEveryBundledComponent() throws {
        let notices = try Self.noticesText()

        // The project's own top-level copyright statement.
        #expect(notices.contains("Copyright (C) 2026 Alexander Kurganov"))

        // A genuine permission notice is present, not merely a bare copyright line.
        #expect(notices.contains(
            "The above copyright notice and this permission notice shall be included in all"
        ))

        // WhisperKit (argmax-oss-swift), MIT.
        #expect(notices.contains("Copyright (c) 2024 argmax, inc."))
        // Its Apache-2.0 portion: swift-transformers, reproduced from the NOTICES file.
        #expect(notices.contains("Copyright 2022 Hugging Face SAS."))
        #expect(notices.contains("Apache License"))
        #expect(notices.contains("Version 2.0, January 2004"))

        // GRDB.swift, MIT.
        #expect(notices.contains("Copyright (C) 2015-2025 Gwendal Roué"))

        // Settings and LaunchAtLogin-Modern (identical sindresorhus MIT bodies):
        // both credited independently by header and source.
        #expect(notices.contains("Copyright (c) Sindre Sorhus <sindresorhus@gmail.com>"))
        #expect(notices.contains("## Settings"))
        #expect(notices.contains("sindresorhus/Settings"))
        #expect(notices.contains("## LaunchAtLogin-Modern"))
        #expect(notices.contains("sindresorhus/LaunchAtLogin-Modern"))

        // Sparkle, MIT.
        #expect(notices.contains("Copyright (c) 2015-2017 Mayur Pawashe."))
        // Sparkle's four grouped external notices.
        #expect(notices.contains("Copyright 2003-2005 Colin Percival"))                 // bsdiff (BSD-2)
        #expect(notices.contains("Copyright (c) 2008-2010 Yuta Mori All Rights Reserved.")) // sais-lite (MIT)
        #expect(notices.contains("Copyright (c) 2015 Orson Peters <orsonpeters@gmail.com>")) // ed25519 (zlib)
        #expect(notices.contains("Copyright (c) 2011 Mark Hamlin."))                    // SUSignatureVerifier (BSD-2)

        // The not-bundled dependency is disclosed honestly, not silently credited.
        #expect(notices.contains("swift-argument-parser"))
    }

    /// The release `app` phase must install the notices artifact into
    /// Contents/Resources, and it must do so BEFORE the app bundle is sealed by
    /// codesign — a resource added after signing would break the seal.
    /// Stated sensitivity: drop the install step → the dest path is absent → RED;
    /// move the install after the app codesign → the ordered-needle scan (notices
    /// install before the slovo.entitlements codesign) → RED.
    /// RED today: the script does not install the notices file, so neither the
    /// presence nor the ordering assertion holds.
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

    /// The dev launcher stages the same bundle shape as the release pipeline, so it
    /// too must copy the notices artifact into Contents/Resources during staging —
    /// which runs entirely before `sign_bundle`, keeping the file present before the
    /// signature is applied.
    /// Stated sensitivity: drop the copy from `stage_bundle` → the body scan for the
    /// notices file into Resources → RED.
    /// RED today: `stage_bundle` does not copy the notices file.
    @Test
    func devLauncherStagesNoticesIntoResources() throws {
        let launcher = try Self.source("Scripts/build_and_run.sh")
        let script = Self.strippingShellComments(from: launcher)
        let stage = try #require(Self.shellFunctionBody(named: "stage_bundle", in: script))

        #expect(stage.contains("THIRD-PARTY-NOTICES.md"), Comment(rawValue: stage))
        #expect(stage.contains("Resources/THIRD-PARTY-NOTICES.md"), Comment(rawValue: stage))
    }

    // MARK: - Helpers (copies of the AppShellPackagingTests / SparklePackagingGuardTests helpers)

    private static func noticesText() throws -> String {
        try String(contentsOf: packageRoot.appending(path: "THIRD-PARTY-NOTICES.md"), encoding: .utf8)
    }

    private static func source(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot.appending(path: relativePath), encoding: .utf8)
    }

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

    private static var packageRoot: URL {
        let testFile = URL(fileURLWithPath: "\(#filePath)")
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
