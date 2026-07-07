import Foundation
import Testing

// Epic 09c — static CI checks for the app-shell/package artifacts. Real launch,
// glyph rendering, signing, notarization, and TCC persistence are L4.
@Suite("Epic 09c app shell and packaging artifacts")
struct AppShellPackagingTests {
    @Test
    func appShellUsesAccessoryMenuBarShape() throws {
        let main = try Self.strippingComments(from: String(
            contentsOfFile: Self.packageRoot.appending(path: "Sources/slovo/main.swift").path,
            encoding: .utf8
        ))
        let appMainMenu = try Self.strippingComments(from: String(
            contentsOfFile: Self.packageRoot.appending(path: "Sources/slovo/AppMainMenu.swift").path,
            encoding: .utf8
        ))
        let delegate = try Self.strippingComments(from: String(
            contentsOfFile: Self.packageRoot.appending(path: "Sources/slovo/AppDelegate.swift").path,
            encoding: .utf8
        ))
        let glyph = try Self.strippingComments(from: String(
            contentsOfFile: Self.packageRoot.appending(path: "Sources/slovo/AppDelegate+Glyph.swift").path,
            encoding: .utf8
        ))

        #expect(main.contains("setActivationPolicy(.accessory)"))
        #expect(main.contains("app.mainMenu = AppMainMenu.make()"))
        #expect(appMainMenu.contains(#"NSMenu(title: "Edit")"#))
        #expect(appMainMenu.contains(#"#selector(NSText.paste(_:))"#))
        #expect(appMainMenu.contains(#"#selector(NSText.selectAll(_:))"#))
        #expect(delegate.contains("NSStatusItem"))
        #expect(delegate.contains("setStatusGlyph(.idle"))
        #expect(glyph.contains("NotoSansGlagolitic-Regular"))
        #expect(glyph.contains("button.image"))
        #expect(!glyph.contains("button?.title = String(MenuBarGlyph"))
    }

    @Test
    func appShellBuildsProductionCompositionAndRoutesHotkey() throws {
        let composition = try Self.strippingComments(from: Self.source("Sources/slovo/AppComposition.swift"))
        let delegate = try Self.strippingComments(from: Self.source("Sources/slovo/AppDelegate.swift"))

        #expect(composition.contains("ConfigStore.load(from: defaults)"))
        // Stated sensitivity: leave production ASR on the abandoned Apple-Speech
        // migration (`SystemSpeechTranscriber(configuration:`) instead of building
        // the restored `WhisperKitTranscriber` → both assertions go RED.
        #expect(!composition.contains("SystemSpeechTranscriber(configuration:"))
        #expect(composition.contains("WhisperKitTranscriber("))
        #expect(composition.contains("OpenRouterCleaner("))
        #expect(composition.contains("ClipboardPasteInjector("))
        #expect(composition.contains("GRDBPersonalizationSource(database:"))
        #expect(composition.contains("CoreAudioOutputMute()"))
        #expect(composition.contains("AVAudioEngineRecorder(authorizer:"))
        #expect(composition.contains("PipelineFactory.makeOrchestrator"))
        #expect(composition.contains("vocabularyLimit: vocabularyLimit"))
        #expect(composition.contains("keepWarmSeconds: config.keepWarmSeconds"))
        #expect(composition.contains("warmUp()"),
                "startup composition must preload the resident ASR engine via warmUp()")
        #expect(composition.contains("statusReporter: statusReporter"))
        #expect(composition.contains("CGEventTapHotkeyMonitor()"))
        let menuBody = try Self.functionBody(named: "makeMenu", in: delegate)
        let launchBody = try Self.functionBody(named: "applicationDidFinishLaunching", in: delegate)
        #expect(Self.containsStatement(#"startPipeline\(\)"#, in: launchBody),
                "launch must invoke the production composition starter, not merely define it elsewhere")
        let startPipelineBody = try Self.functionBody(named: "startPipeline", in: delegate)
        let showStatusBody = try Self.functionBody(named: "showStatus", in: delegate)
        #expect(delegate.contains("guard live.onboardingSteps == [.ready]"))
        #expect(delegate.contains("presentOnboarding(live.onboardingSteps)"))
        #expect(delegate.contains("x-apple.systempreferences:com.apple.preference.security?"))
        #expect(delegate.contains("promptForOpenRouterKey"))
        #expect(delegate.contains("composition?.openRouterKeyProvider"))
        #expect(delegate.contains("try provider.store(key)"))
        #expect(menuBody.contains(#"actionItem("Update OpenRouter Key", #selector(enterOpenRouterKey))"#))
        #expect(menuBody.contains(#""Cleanup Model: \(CleanupModelCatalog.displayName"#))
        #expect(menuBody.contains("selectedModel: config.openRouterModel"))
        #expect(delegate.contains("statusReporter"))
        #expect(delegate.contains("showStatus"))
        #expect(delegate.contains("setStatusGlyph(status"))
        #expect(delegate.contains("Task.sleep(for: .seconds(5))"))
        #expect(delegate.contains("didShowPipelineStatus"))
        #expect(Self.statementCount(#"self\?\.didShowPipelineStatus\s*=\s*false"#, in: startPipelineBody) == 1,
                "pipeline status may reset at operation start, but key-up must preserve any start-failure status")
        #expect(Self.containsStatement(#"if\s+self\?\.didShowPipelineStatus\s*==\s*false\s*\{"#, in: startPipelineBody))
        #expect(Self.statementCount(#"if\s+self\?\.didShowPipelineStatus\s*==\s*false\s*\{"#, in: startPipelineBody) == 2,
                "key-up must guard both Processing and Idle labels so failures are not overwritten")
        #expect(Self.containsStatement(#"didShowPipelineStatus\s*=\s*true"#, in: showStatusBody))
        #expect(delegate.contains("live.hotkeyMonitor.start()"))
        #expect(delegate.contains("setStatusGlyph(.recording"))
        #expect(delegate.contains("setStatusGlyph(.processing"))
        #expect(delegate.contains("awaitPipelineDrain()"))
        #expect(delegate.contains("orchestrator.handle(.startRequested)"))
        #expect(delegate.contains("orchestrator.handle(.stopRequested)"))
    }

    @Test
    func infoPlistDeclaresMenuBarAgentAndTccUsage() throws {
        let data = try Data(contentsOf: Self.packageRoot.appending(path: "Resources/Info.plist"))
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        #expect(plist["LSUIElement"] as? Bool == true)
        #expect(plist["CFBundleIdentifier"] as? String == "com.slovo.app")
        #expect(plist["CFBundleExecutable"] as? String == "slovo")
        #expect(plist["NSPrincipalClass"] as? String == "NSApplication")
        #expect((plist["NSMicrophoneUsageDescription"] as? String)?.isEmpty == false)
        #expect((plist["NSSpeechRecognitionUsageDescription"] as? String)?.isEmpty == false)
        #expect(plist["LSMinimumSystemVersion"] as? String == "26.0")
    }

    @Test
    func entitlementsAllowAudioInputWithoutSandbox() throws {
        let data = try Data(contentsOf: Self.packageRoot.appending(path: "slovo.entitlements"))
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        #expect(plist["com.apple.security.device.audio-input"] as? Bool == true)
        #expect(plist["com.apple.security.app-sandbox"] == nil)
    }

    @Test
    func signingScriptUsesHardenedRuntimeAndOptionalNotarization() throws {
        let source = try String(
            contentsOf: Self.packageRoot.appending(path: "Scripts/sign-and-notarize.sh"),
            encoding: .utf8
        )

        #expect(source.contains("codesign"))
        #expect(source.contains("--options runtime"))
        #expect(source.contains("slovo.entitlements"))
        #expect(source.contains("notarytool"))
        #expect(source.contains("stapler"))
        #expect(source.contains("validate_app_name"))
        #expect(source.contains("*/*|*..*"))
        #expect(source.contains("already exists"))
        #expect(source.contains("--cache-path \"$SWIFTPM_CACHE_DIR\""))
        #expect(source.contains("--config-path \"$SWIFTPM_CONFIG_DIR\""))
        #expect(source.contains("--security-path \"$SWIFTPM_SECURITY_DIR\""))
        #expect(source.contains("--disable-automatic-resolution"))
        #expect(!source.contains("rm -rf"))

        let syntax = try Self.run("/bin/bash", arguments: ["-n", Self.scriptPath])
        #expect(syntax.exitCode == 0, Comment(rawValue: syntax.output))

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

        let invalidName = try Self.scriptPlan(["app"], appName: "../../bad")
        #expect(invalidName.exitCode == 64, Comment(rawValue: invalidName.output))
        #expect(!invalidName.output.contains("DRY-RUN codesign"))

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

    private static func source(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot.appending(path: relativePath), encoding: .utf8)
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

    private static func containsStatement(_ pattern: String, in source: String) -> Bool {
        statementCount(pattern, in: source) > 0
    }

    private static func statementCount(_ pattern: String, in source: String) -> Int {
        let code = strippingStringLiterals(from: source)
        let expression = try? NSRegularExpression(pattern: #"(?m)^\s*\#(pattern)\s*$"#)
        let range = NSRange(code.startIndex..<code.endIndex, in: code)
        return expression?.numberOfMatches(in: code, range: range) ?? 0
    }

    private static func strippingStringLiterals(from source: String) -> String {
        var output = ""
        var index = source.startIndex
        var inString = false
        var escaped = false

        while index < source.endIndex {
            let character = source[index]
            if inString {
                if character == "\n" {
                    output.append(character)
                } else if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                    output.append(character)
                }
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

    private static func functionBody(named name: String, in source: String) throws -> String {
        guard let signature = source.range(of: "func \(name)") else {
            throw NSError(domain: "AppShellPackagingTests", code: 1)
        }
        guard let openBrace = functionOpeningBrace(after: signature.lowerBound, in: source) else {
            throw NSError(domain: "AppShellPackagingTests", code: 2)
        }
        var depth = 0
        var index = openBrace
        while index < source.endIndex {
            if source[index] == "{" {
                depth += 1
            } else if source[index] == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[openBrace...index])
                }
            }
            index = source.index(after: index)
        }
        throw NSError(domain: "AppShellPackagingTests", code: 3)
    }

    private static func functionOpeningBrace(after start: String.Index, in source: String) -> String.Index? {
        var index = start
        var parenDepth = 0
        while index < source.endIndex {
            if source[index] == "(" {
                parenDepth += 1
            } else if source[index] == ")" {
                parenDepth -= 1
            } else if source[index] == "{", parenDepth == 0 {
                return index
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static var packageRoot: URL {
        let testFile = URL(fileURLWithPath: "\(#filePath)")
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
