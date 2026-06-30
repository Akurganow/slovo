import Foundation
import Testing

import LoquiCore

@Suite("App runtime source guards")
struct AppRuntimeSourceGuardTests {
    @Test
    func firstRunPermissionRequestsTccBeforeOpeningSettings() throws {
        let permissions = try Self.code("Sources/LoquiCore/Permissions/PermissionPreflighter.swift")
        let systemPermissions = try Self.code("Sources/LoquiCore/Permissions/SystemPermissionPreflighter.swift")
        let delegate = try Self.code("Sources/loqui/AppDelegate.swift")
        let composition = try Self.code("Sources/loqui/AppComposition.swift")
        let systemRequestBody = try Self.functionBody(named: "request", in: systemPermissions)
        let requestMicrophoneBody = try Self.functionBody(named: "requestMicrophoneAccess", in: systemPermissions)
        let requestAccessibilityBody = try Self.functionBody(named: "requestAccessibilityAccess", in: systemPermissions)
        let requestInputMonitoringBody = try Self.functionBody(named: "requestInputMonitoringAccess", in: systemPermissions)
        let requestBody = try Self.functionBody(named: "requestPermission", in: delegate)
        let primaryBody = try Self.functionBody(named: "requestPrimaryOnboardingStep", in: delegate)

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
        #expect(primaryBody.contains("await requestPermission(.inputMonitoring"))
        #expect(!delegate.contains("requestPermission(.requestMicrophone"))
        #expect(!delegate.contains("requestPermission(.requestAccessibility"))
        #expect(!delegate.contains("requestPermission(.requestInputMonitoring"))
    }

    @Test
    func appStartupChecksKeyPresenceWithoutDecryptingSecret() throws {
        let composition = try Self.code("Sources/loqui/AppComposition.swift")
        let keyProvider = try Self.code("Sources/LoquiCore/Cleaner/KeychainAnthropicKeyProvider.swift")
        let makeLiveBody = try Self.functionBody(named: "makeLive", in: composition)
        let hasConfiguredKeyBody = try Self.functionBody(named: "hasConfiguredKey", in: keyProvider)
        let keychainItemExistsBody = try Self.functionBody(named: "keychainItemExists", in: keyProvider)

        #expect(Self.containsStatement(#"hasKey:\s*keyProvider\.hasConfiguredKey\(\),?"#, in: makeLiveBody))
        #expect(!Self.withoutStringLiterals(makeLiveBody).contains("keyProvider.apiKey()"))
        #expect(hasConfiguredKeyBody.contains("keychainItemExists()"))
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
    func transientProgressStatusDoesNotBecomeSticky() throws {
        let delegate = try Self.code("Sources/loqui/AppDelegate.swift")
        let startPipelineBody = try Self.functionBody(named: "startPipeline", in: delegate)
        let showStatusBody = try Self.functionBody(named: "showStatus", in: delegate)

        #expect(!StatusMessage.preparingSpeechModel.isPersistentNotice)
        #expect(StatusMessage.cleanupFailed.isPersistentNotice)
        #expect(Self.containsStatement(
            #"guard status\.isPersistentNotice \|\| isPipelineActive else \{ return \}"#,
            in: showStatusBody
        ))
        #expect(Self.containsInOrder([
            "if status.isPersistentNotice",
            "didShowPipelineStatus = true",
            "statusTextItem?.title",
        ], in: showStatusBody))
        #expect(Self.statementCount(#"self\?\.isPipelineActive\s*=\s*true"#, in: startPipelineBody) == 1)
        #expect(Self.statementCount(#"self\?\.isPipelineActive\s*=\s*false"#, in: startPipelineBody) == 1)
        #expect(Self.containsInOrder([
            "self?.isPipelineActive = true",
            "self?.didShowPipelineStatus = false",
        ], in: startPipelineBody))
        #expect(Self.containsInOrder([
            "await orchestrator.awaitPipelineDrain()",
            "self?.setStatusGlyph(.idle",
            "self?.isPipelineActive = false",
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
