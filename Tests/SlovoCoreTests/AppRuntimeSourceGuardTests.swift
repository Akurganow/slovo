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
        let config = try Self.code("Sources/SlovoCore/Config/Config.swift")
        let configStore = try Self.code("Sources/SlovoCore/Config/ConfigStore.swift")
        let pipelineFactory = try Self.code("Sources/SlovoCore/Composition/PipelineFactory.swift")
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
        for forbidden in ["cleanupEnabled", "cleanupToggleItem", "toggleCleanupEnabled", "Cleanup: Disabled"] {
            for source in [delegate, cleanupMenu, config, pipelineFactory] {
                #expect(!source.contains(forbidden), "runtime source must not expose \(forbidden)")
            }
        }
        #expect(!Self.withoutStringLiterals(configStore).contains("cleanupEnabled"))
        #expect(!Self.withoutStringLiterals(configStore).contains("enabled: false"))
        #expect(modelMenuBody.contains("CleanupModelCatalog.options"))
        #expect(modelMenuBody.contains("item.representedObject = option"))
        #expect(modelMenuBody.contains("item.state = option.id == selectedModel ? .on : .off"))
        #expect(modelMenuBody.contains(#"actionItem("Custom Model...", #selector(promptForCustomCleanupModel))"#))
        #expect(selectCleanupModelBody.contains("sender.representedObject as? CleanupModelOption"))
        #expect(selectCleanupModelBody.contains("applyCleanupModel(option.id)"))
    }

    /// #2: switching the cleanup model must apply live to the next dictation. It
    /// must NOT tear down and rebuild the pipeline, because a rebuild re-warms the
    /// ASR model and shows the "Preparing Speech Model" loading pulse — alarming
    /// and misleading for a change that only swaps the cleanup LLM id.
    /// Stated sensitivity: route the cleanup-model change back through
    /// retrySetup()/startPipeline (a pipeline rebuild) or drop the live
    /// orchestrator update → RED.
    @Test
    func changingCleanupModelAppliesLiveWithoutPipelineRebuild() throws {
        let delegate = try Self.code("Sources/slovo/AppDelegate.swift")
        let cleanupMenu = try Self.code("Sources/slovo/AppDelegate+CleanupMenu.swift")
        let orchestrator = try Self.code("Sources/SlovoCore/Orchestrator.swift")
        let selectBody = try Self.functionBody(named: "selectCleanupModel", in: cleanupMenu)
        let customBody = try Self.functionBody(named: "promptForCustomCleanupModel", in: cleanupMenu)
        let applyBody = try Self.functionBody(named: "applyCleanupModel", in: delegate)

        #expect(selectBody.contains("applyCleanupModel(option.id)"))
        #expect(customBody.contains("applyCleanupModel("))

        for forbidden in ["retrySetup", "startPipeline", "prepareModelGate", "showModelLoadingState"] {
            #expect(!applyBody.contains(forbidden),
                    "changing the cleanup model must not \(forbidden): that re-warms ASR and shows the loading pulse")
        }
        #expect(applyBody.contains("updateCleanupConfig"),
                "the cleanup-model change must apply live to the running orchestrator")
        #expect(orchestrator.contains("func updateCleanupConfig"),
                "the orchestrator must expose a live cleanup-config update so no rebuild is needed")
        #expect(!delegate.contains("func updateConfig"),
                "the generic rebuild-on-any-config-change path is the #2 bug vector and must be gone")
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

    /// Production dictation is the restored WhisperKit transcriber, and the on-device
    /// model cache must never live under the user's `Documents`. The WhisperKit SDK's
    /// DEFAULT download location is `~/Documents/huggingface` — and it lives in the SDK,
    /// so a grep-for-"Documents" over our source is FALSE-GREEN. `WhisperKitEngine` must
    /// POSITIVELY override it with an explicit `WhisperKitConfig.downloadBase` under
    /// Application Support. Stated sensitivity: revert to the SDK default (drop
    /// downloadBase / applicationSupportDirectory) → RED; ASR not built as
    /// WhisperKitTranscriber → composition RED; a Documents marker anywhere → RED.
    @Test
    func productionAsrEngineSetsNonDocumentsModelDownloadBase() throws {
        let sources = try Self.productionAsrRuntimeSources()
        let sourceByPath = Dictionary(uniqueKeysWithValues: sources.map { ($0.relativePath, $0.contents) })
        let composition = try #require(sourceByPath["Sources/slovo/AppComposition.swift"])
        let engine = try #require(sourceByPath["Sources/SlovoCore/ASR/WhisperKitEngine.swift"])

        #expect(composition.contains("WhisperKitTranscriber("))
        #expect(engine.contains("downloadBase"),
                "WhisperKitEngine must set WhisperKitConfig.downloadBase to override the SDK's ~/Documents default")
        #expect(engine.contains("applicationSupportDirectory"),
                "the model download base must resolve under Application Support, not Documents")
        for forbidden in [
            ".documentDirectory", ".documentsDirectory", "URL.documentsDirectory",
            "FileManager.default.url(for: .documentDirectory",
            "FileManager.default.urls(for: .documentDirectory",
            "FileManager.SearchPathDirectory.documentDirectory", "documentDirectory", "Documents",
        ] {
            for source in sources {
                #expect(!source.contents.contains(forbidden),
                        "\(source.relativePath) must not cache the ASR model under the user's Documents (\(forbidden))")
            }
        }
    }

    @Test
    func transientProgressAndSadToFailStatusDoNotBecomeSticky() throws {
        let delegate = try Self.code("Sources/slovo/AppDelegate.swift")
        let startPipelineBody = try Self.functionBody(named: "startPipeline", in: delegate)
        let showStatusBody = try Self.functionBody(named: "showStatus", in: delegate)

        #expect(!StatusMessage.preparingSpeechModel.isPersistentNotice)
        #expect(StatusMessage.cleanupUnavailableInsertedAsSpoken.isSadToFailNotice)
        #expect(!StatusMessage.cleanupUnavailableInsertedAsSpoken.isPersistentNotice)
        #expect(Self.statementCount(
            #"guard status\.isPersistentNotice \|\| status\.isSadToFailNotice \|\| isPipelineActive else \{"#,
            in: showStatusBody
        ) > 0)
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
}
