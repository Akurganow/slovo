import Foundation
import Testing

import SlovoCore

@Suite("App runtime source guards")
struct AppRuntimeSourceGuardTests {
    @Test
    func firstRunPermissionRequestsTccBeforeOpeningSettings() throws {
        let permissions = try Self.code("Sources/SlovoCore/Permissions/PermissionPreflighter.swift")
        let systemPermissions = try Self.code("Sources/SlovoCore/Permissions/SystemPermissionPreflighter.swift")
        let delegate = try Self.code("Sources/slovo/AppDelegate.swift")
        let composition = try Self.code("Sources/slovo/AppComposition.swift")
        let systemRequestBody = try Self.functionBody(named: "request", in: systemPermissions)
        let requestMicrophoneBody = try Self.functionBody(named: "requestMicrophoneAccess", in: systemPermissions)
        let requestAccessibilityBody = try Self.functionBody(named: "requestAccessibilityAccess", in: systemPermissions)
        let requestInputMonitoringBody = try Self.functionBody(named: "requestInputMonitoringAccess", in: systemPermissions)
        let requestBody = try Self.functionBody(named: "requestPermission", in: delegate)
        let primaryBody = try Self.functionBody(named: "requestPrimaryOnboardingStep", in: delegate)
        let startPipelineBody = try Self.functionBody(named: "startPipeline", in: delegate)
        let hotkeyMenuBody = try Self.functionBody(named: "makeHotkeyRecoveryMenu", in: delegate)

        #expect(permissions.contains("public enum SystemPermission: Equatable, Sendable"))
        #expect(permissions.contains("func request(_ permission: SystemPermission) async -> Bool"))
        #expect(!permissions.contains("func request(_ step: OnboardingStep) async -> Bool"))
        #expect(systemPermissions.contains("AVCaptureDevice.requestAccess(for: .audio)"))
        #expect(systemPermissions.contains("AXIsProcessTrustedWithOptions(options)"))
        #expect(systemPermissions.contains("CGRequestListenEventAccess()"))
        #expect(Self.containsInOrder([
            "switch permission",
            "case .microphone:",
            "await requestMicrophoneAccess()",
            "case .accessibility:",
            "requestAccessibilityAccess()",
            "case .inputMonitoring:",
            "requestInputMonitoringAccess()",
        ], in: systemRequestBody))
        #expect(requestMicrophoneBody.contains("AVCaptureDevice.requestAccess(for: .audio)"))
        #expect(requestMicrophoneBody.contains("continuation.resume(returning: granted)"))
        #expect(requestAccessibilityBody.contains("AXIsProcessTrustedWithOptions(options)"))
        #expect(requestInputMonitoringBody.contains("CGRequestListenEventAccess()"))
        #expect(composition.contains("permissionRequester: permissionPreflighter"))
        #expect(Self.statementCount(#"openSettingsPane\(fallbackPane\)"#, in: requestBody) == 2)
        #expect(Self.containsInOrder([
            "guard let permissionRequester = composition?.permissionRequester else",
            "openSettingsPane(fallbackPane)",
            "return",
            "let granted = await permissionRequester.request(permission)",
            "if granted",
            "retrySetup()",
            "openSettingsPane(fallbackPane)",
        ], in: requestBody))
        #expect(primaryBody.contains("await requestPermission(.microphone"))
        #expect(primaryBody.contains("await requestPermission(.accessibility"))
        #expect(!primaryBody.contains("await requestPermission(.inputMonitoring"))
        #expect(Self.containsInOrder([
            "do",
            "try live.hotkeyMonitor.start()",
            "catch",
            "presentHotkeyRecovery()",
        ], in: startPipelineBody))
        #expect(hotkeyMenuBody.contains("Request Input Monitoring Access"))
        #expect(hotkeyMenuBody.contains("#selector(openInputMonitoringSettings)"))
        #expect(delegate.contains("showHotkeyRecoveryAlertIfNeeded"))
        #expect(delegate.contains("Slovo could not start the hold-to-talk hotkey."))
        #expect(!delegate.contains("Slovo needs setup before dictation starts.\\nInput Monitoring"))
        #expect(delegate.contains("NSMenuDelegate"))
        #expect(delegate.contains("menu.delegate = self"))
        #expect(delegate.contains("func menuNeedsUpdate(_ menu: NSMenu)"))
        #expect(delegate.contains("refreshOnboardingMenuIfNeeded()"))
        #expect(delegate.contains("FirstRunFlow.pendingSteps(permissions: SystemPermissionPreflighter().preflight())"))
        #expect(delegate.contains(#"private static let setupAlertStepsKey = "setup.alert.steps""#))
        #expect(delegate.contains("showOnboardingAlertIfNeeded(for: steps)"))
        #expect(delegate.contains("defaults.string(forKey: Self.setupAlertStepsKey)"))
        #expect(delegate.contains("defaults.set(signature, forKey: Self.setupAlertStepsKey)"))
        #expect(delegate.contains("defaults.removeObject(forKey: Self.setupAlertStepsKey)"))
        #expect(!delegate.contains("requestPermission(.requestMicrophone"))
        #expect(!delegate.contains("requestPermission(.requestAccessibility"))
        #expect(!delegate.contains("requestPermission(.requestInputMonitoring"))
    }

    @Test
    func readinessCheckUsesKeyPresenceWithoutDecryptingSecret() throws {
        let composition = try Self.code("Sources/slovo/AppComposition.swift")
        let keyProvider = try Self.code("Sources/SlovoCore/Cleaner/KeychainAPIKeyProvider.swift")
        let makeLiveBody = try Self.functionBody(named: "makeLive", in: composition)
        let hasConfiguredKeyBody = try Self.functionBody(named: "hasConfiguredKey", in: keyProvider)
        let keychainItemExistsBody = try Self.functionBody(named: "keychainItemExists", in: keyProvider)

        #expect(makeLiveBody.contains("FirstRunFlow.pendingSteps("))
        #expect(!makeLiveBody.contains("hasOpenRouterKey"))
        #expect(!Self.withoutStringLiterals(makeLiveBody).contains("keyProvider.apiKey()"))
        #expect(hasConfiguredKeyBody.contains("keyExists()"))
        for forbidden in ["apiKey()", "keychainKey()", "kSecReturnData"] {
            #expect(!Self.withoutStringLiterals(hasConfiguredKeyBody).contains(forbidden),
                    "hasConfiguredKey must not read or decrypt the stored secret via \(forbidden)")
        }
        #expect(keychainItemExistsBody.contains("kSecReturnAttributes as String: true"))
        #expect(keychainItemExistsBody.contains("kSecMatchLimit as String: kSecMatchLimitOne"))
        #expect(keychainItemExistsBody.contains("SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess"))
        for forbidden in ["apiKey()", "keychainKey()", "kSecReturnData"] {
            #expect(!Self.withoutStringLiterals(keychainItemExistsBody).contains(forbidden),
                    "keychainItemExists must stay attributes-only and must not read the secret via \(forbidden)")
        }
    }

    @Test
    func readyPipelineDoesNotRequireCleanupKeyBeforeHotkeyStart() throws {
        let delegate = try Self.code("Sources/slovo/AppDelegate.swift")
        let startPipelineBody = try Self.functionBody(named: "startPipeline", in: delegate)

        #expect(Self.containsInOrder([
            "guard live.onboardingSteps == [.ready] else",
            "try live.hotkeyMonitor.start()",
        ], in: startPipelineBody))
        #expect(!startPipelineBody.contains("openRouterKeyProvider.preload()"),
                "launch must not read the Keychain secret; cleanup reads it lazily when needed")
    }

    @Test
    func appMenuSelectsOpenRouterModelAndShowsCurrentModel() throws {
        let delegate = try Self.code("Sources/slovo/AppDelegate.swift")
        let cleanupMenu = try Self.code("Sources/slovo/AppDelegate+CleanupMenu.swift")
        let menuBody = try Self.functionBody(named: "makeMenu", in: delegate)
        let modelMenuBody = try Self.functionBody(named: "modelMenu", in: cleanupMenu)
        let selectCleanupModelBody = try Self.functionBody(named: "selectCleanupModel", in: cleanupMenu)

        #expect(!menuBody.contains("cleanupProviderMenu(config: config)"))
        #expect(!menuBody.contains(#"modelMenu(title: "Anthropic Model""#))
        #expect(!menuBody.contains(#"modelMenu(title: "OpenAI Model""#))
        #expect(menuBody.contains(#""Cleanup Model: \(CleanupModelCatalog.displayName"#))
        #expect(menuBody.contains("selectedModel: config.openRouterModel"))
        #expect(!menuBody.contains(#"modelMenu(title: "Local Model""#))
        #expect(!delegate.contains("Use Anthropic Cleanup"))
        #expect(!delegate.contains("Use OpenAI Cleanup"))
        #expect(!delegate.contains("promptForModel"))
        #expect(!delegate.contains("Set Anthropic Model"))
        #expect(!delegate.contains("Set OpenAI Model"))
        #expect(modelMenuBody.contains("CleanupModelCatalog.options"))
        #expect(modelMenuBody.contains("item.representedObject = option"))
        #expect(modelMenuBody.contains("item.state = option.id == selectedModel ? .on : .off"))
        #expect(modelMenuBody.contains(#"actionItem("Custom Model...", #selector(promptForCustomCleanupModel))"#))
        #expect(selectCleanupModelBody.contains("sender.representedObject as? CleanupModelOption"))
        #expect(selectCleanupModelBody.contains("config.openRouterModel = option.id"))
    }

    @Test
    func appRuntimeDoesNotLinkOrWarmLocalCleanupModels() throws {
        let composition = try Self.code("Sources/slovo/AppComposition.swift")
        let delegate = try Self.code("Sources/slovo/AppDelegate.swift")
        let makeLiveBody = try Self.functionBody(named: "makeLive", in: composition)

        #expect(!composition.contains("import SlovoLocalModels"))
        #expect(!composition.contains("MLXCleaner("))
        #expect(!makeLiveBody.contains("localCleanupModel"))
        #expect(!delegate.contains("startLocalCleanupModelWarmupIfNeeded"))
        #expect(!delegate.contains("preparingCleanupModel"))
        #expect(!delegate.contains("cleanupModelReady"))
    }

    @Test
    func transientProgressAndSadToFailStatusDoNotBecomeSticky() throws {
        let delegate = try Self.code("Sources/slovo/AppDelegate.swift")
        let startPipelineBody = try Self.functionBody(named: "startPipeline", in: delegate)
        let showStatusBody = try Self.functionBody(named: "showStatus", in: delegate)

        #expect(!StatusMessage.preparingSpeechModel.isPersistentNotice)
        #expect(StatusMessage.cleanupUnavailableInsertedAsSpoken.isSadToFailNotice)
        #expect(!StatusMessage.cleanupUnavailableInsertedAsSpoken.isPersistentNotice)
        #expect(Self.containsStatement(
            #"guard status\.isPersistentNotice \|\| status\.isSadToFailNotice \|\| isPipelineActive else \{"#,
            in: showStatusBody
        ))
        #expect(Self.containsInOrder([
            "if status.isPersistentNotice",
            "didShowPipelineStatus = true",
            "statusTextItem?.title",
        ], in: showStatusBody))
        #expect(Self.containsInOrder([
            "if status.isSadToFailNotice",
            "setStatusGlyph(status",
            "Task { @MainActor",
            "try? await Task.sleep(for: .seconds(5))",
            "setStatusGlyph(.idle",
        ], in: showStatusBody))
        #expect(Self.statementCount(#"self\?\.isPipelineActive\s*=\s*true"#, in: startPipelineBody) == 1)
        #expect(Self.statementCount(#"self\?\.isPipelineActive\s*=\s*false"#, in: startPipelineBody) == 1)
        #expect(Self.containsInOrder([
            "self?.isPipelineActive = true",
            "self?.didShowPipelineStatus = false",
        ], in: startPipelineBody))
        #expect(Self.containsInOrder([
            "await orchestrator.awaitPipelineDrain()",
            "self?.isPipelineActive = false",
            "if self?.isShowingSadToFailStatus == false",
            "self?.setStatusGlyph(.idle",
            "if self?.didShowPipelineStatus == false",
        ], in: startPipelineBody))
    }

    private static func code(_ relativePath: String) throws -> String {
        try strippingComments(from: String(contentsOf: packageRoot.appending(path: relativePath), encoding: .utf8))
    }

    private static func containsStatement(_ pattern: String, in source: String) -> Bool {
        statementCount(pattern, in: source) > 0
    }

    private static func statementCount(_ pattern: String, in source: String) -> Int {
        let code = withoutStringLiterals(source)
        let expression = try? NSRegularExpression(pattern: #"(?m)^\s*\#(pattern)\s*$"#)
        let range = NSRange(code.startIndex..<code.endIndex, in: code)
        return expression?.numberOfMatches(in: code, range: range) ?? 0
    }

    private static func containsInOrder(_ needles: [String], in source: String) -> Bool {
        var searchStart = source.startIndex
        for needle in needles {
            guard let range = source.range(of: needle, range: searchStart..<source.endIndex) else {
                return false
            }
            searchStart = range.upperBound
        }
        return true
    }

    private static func functionBody(named name: String, in source: String) throws -> String {
        guard let signature = source.range(of: "func \(name)") else {
            throw NSError(domain: "AppRuntimeSourceGuardTests", code: 1)
        }
        guard let openBrace = functionOpeningBrace(after: signature.lowerBound, in: source) else {
            throw NSError(domain: "AppRuntimeSourceGuardTests", code: 2)
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
        throw NSError(domain: "AppRuntimeSourceGuardTests", code: 3)
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

    private static func withoutStringLiterals(_ source: String) -> String {
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

    private static var packageRoot: URL {
        let testFile = URL(fileURLWithPath: "\(#filePath)")
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
