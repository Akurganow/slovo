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
        let delegate = try Self.strippingComments(from: String(
            contentsOfFile: Self.packageRoot.appending(path: "Sources/slovo/AppDelegate.swift").path,
            encoding: .utf8
        ))
        let glyph = try Self.strippingComments(from: String(
            contentsOfFile: Self.packageRoot.appending(path: "Sources/slovo/AppDelegate+Glyph.swift").path,
            encoding: .utf8
        ))

        #expect(main.contains("setActivationPolicy(.accessory)"))
        #expect(delegate.contains("NSStatusItem"))
        #expect(delegate.contains("setStatusGlyph(.idle"))
        #expect(glyph.contains("NotoSansGlagolitic-Regular"))
        #expect(delegate.contains("button.image"))
        #expect(!delegate.contains("button?.title = String(MenuBarGlyph"))
    }

    @Test
    func appShellBuildsProductionCompositionAndRoutesHotkey() throws {
        let composition = try Self.strippingComments(from: Self.source("Sources/slovo/AppComposition.swift"))
        let delegate = try Self.strippingComments(from: Self.source("Sources/slovo/AppDelegate.swift"))

        #expect(composition.contains("ConfigStore.load(from: defaults)"))
        #expect(composition.contains("WhisperKitTranscriber(configuration:"))
        #expect(composition.contains("OpenRouterCleaner("))
        #expect(composition.contains("ClipboardPasteInjector("))
        #expect(composition.contains("GRDBPersonalizationSource(database:"))
        #expect(composition.contains("CoreAudioOutputMute()"))
        #expect(composition.contains("AVAudioEngineRecorder(authorizer:"))
        #expect(composition.contains("PipelineFactory.makeOrchestrator"))
        #expect(composition.contains("vocabularyLimit: vocabularyLimit"))
        #expect(composition.contains("keepWarmSeconds: config.keepWarmSeconds"))
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
        #expect(delegate.contains("showOnboardingAlert"))
        #expect(delegate.contains("x-apple.systempreferences:com.apple.preference.security?"))
        #expect(delegate.contains("promptForOpenRouterKey"))
        #expect(!delegate.contains("promptForAnthropicKey"))
        #expect(!delegate.contains("promptForOpenAIKey"))
        #expect(!delegate.contains("composition?.anthropicKeyProvider"))
        #expect(!delegate.contains("composition?.openAIKeyProvider"))
        #expect(delegate.contains("composition?.openRouterKeyProvider"))
        #expect(delegate.contains("try provider.store(key)"))
        #expect(!menuBody.contains(#"actionItem("Update Anthropic Key", #selector(enterAnthropicKey))"#))
        #expect(!menuBody.contains(#"actionItem("Update OpenAI Key", #selector(enterOpenAIKey))"#))
        #expect(menuBody.contains(#"actionItem("Update OpenRouter Key", #selector(enterOpenRouterKey))"#))
        #expect(menuBody.contains(#""Cleanup Model: \(CleanupModelCatalog.displayName"#))
        #expect(menuBody.contains("selectedModel: config.openRouterModel"))
        #expect(!menuBody.contains(#"modelMenu(title: "Local Model""#))
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

        let syntax = try Self.run("/bin/bash", arguments: ["-n", Self.packageRoot.appending(path: "Scripts/sign-and-notarize.sh").path])
        #expect(syntax.exitCode == 0, Comment(rawValue: syntax.output))

        let plan = try Self.run(
            "/bin/bash",
            arguments: [Self.packageRoot.appending(path: "Scripts/sign-and-notarize.sh").path],
            environment: [
                "DRY_RUN": "1",
                "SIGNING_IDENTITY": "Developer ID Application: Example (TEAMID)",
                "NOTARY_PROFILE": "slovo-notary",
                "APP_NAME": "DryRunTestBundle-\(UUID().uuidString)",
            ]
        )
        #expect(plan.exitCode == 0, Comment(rawValue: plan.output))
        #expect(plan.output.contains("--disable-automatic-resolution"), Comment(rawValue: plan.output))
        #expect(Self.output(plan.output, containsInOrder: [
            "DRY-RUN swift build",
            "DRY-RUN install -d",
            "DRY-RUN install",
            "DRY-RUN codesign",
            "DRY-RUN ditto",
            "DRY-RUN xcrun notarytool",
            "DRY-RUN xcrun stapler",
        ]), Comment(rawValue: plan.output))

        let invalidName = try Self.run(
            "/bin/bash",
            arguments: [Self.packageRoot.appending(path: "Scripts/sign-and-notarize.sh").path],
            environment: [
                "DRY_RUN": "1",
                "SIGNING_IDENTITY": "Developer ID Application: Example (TEAMID)",
                "APP_NAME": "../../bad",
            ]
        )
        #expect(invalidName.exitCode == 64, Comment(rawValue: invalidName.output))
        #expect(!invalidName.output.contains("DRY-RUN codesign"))

        let existingName = "ExistingTestBundle"
        let existingPath = Self.packageRoot.appending(path: ".build/dist/\(existingName).app")
        try FileManager.default.createDirectory(at: existingPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: existingPath) }

        let staleBundle = try Self.run(
            "/bin/bash",
            arguments: [Self.packageRoot.appending(path: "Scripts/sign-and-notarize.sh").path],
            environment: [
                "DRY_RUN": "1",
                "SIGNING_IDENTITY": "Developer ID Application: Example (TEAMID)",
                "APP_NAME": existingName,
            ]
        )
        #expect(staleBundle.exitCode == 65, Comment(rawValue: staleBundle.output))
        #expect(!staleBundle.output.contains("DRY-RUN codesign"))
    }

    @Test
    func publicReleaseChecklistCapturesReleaseChecks() throws {
        let source = try String(
            contentsOf: Self.packageRoot.appending(path: "docs/release-checklist.md"),
            encoding: .utf8
        )

        #expect(source.contains("LSUIElement=true"))
        #expect(source.contains("TCC grants survive rebuild"))
        #expect(source.contains("stable development signing identity"))
        #expect(source.contains("codesign --verify --deep --strict --verbose=2"))
        #expect(source.contains("spctl --assess --type execute --verbose"))
        #expect(source.contains("notarytool"))
        #expect(source.contains("stapler"))
        #expect(source.contains("first launch"))
        #expect(source.contains("NotoSansGlagolitic-Regular"))
        #expect(source.contains("biasTerms"))
        #expect(source.contains("PassThrough"))
        #expect(source.contains("privacy"))
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
