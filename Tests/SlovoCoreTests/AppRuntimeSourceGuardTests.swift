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
        let startPipelineBody = try Self.functionBody(named: "startPipeline", in: delegate)
        let hotkeyMenuBody = try Self.functionBody(named: "makeHotkeyRecoveryMenu", in: delegate)

        #expect(permissions.contains("public enum SystemPermission: Equatable, Sendable"))
        #expect(permissions.contains("func request(_ permission: SystemPermission) async -> Bool"))
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
        #expect(delegate.contains("requestPermission(.microphone"))
        #expect(delegate.contains("requestPermission(.accessibility"))
        #expect(Self.containsInOrder([
            "do",
            "try live.hotkeyMonitor.start()",
            "catch",
            "presentHotkeyRecovery()",
        ], in: startPipelineBody))
        #expect(hotkeyMenuBody.contains("Request Input Monitoring Access"))
        #expect(hotkeyMenuBody.contains("#selector(openInputMonitoringSettings)"))
        #expect(delegate.contains("NSMenuDelegate"))
        #expect(delegate.contains("menu.delegate = self"))
        #expect(delegate.contains("func menuNeedsUpdate(_ menu: NSMenu)"))
        #expect(delegate.contains("refreshOnboardingMenuIfNeeded()"))
        #expect(delegate.contains("FirstRunFlow.pendingSteps(permissions: SystemPermissionPreflighter().preflight())"))
        // Onboarding surfaces through the menu-bar setup menu (no modal alert); the
        // menu offers the permission requests directly.
        #expect(delegate.contains("Request Microphone Access"))
        #expect(delegate.contains("Request Accessibility Access"))
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
        let cleanupMenu = try Self.code("Sources/slovo/AppDelegate+CleanupMenu.swift")
        let menuBuilder = try Self.code("Sources/slovo/DictationMenuBuilder.swift")
        let modelMenuBody = try Self.functionBody(named: "modelMenu", in: cleanupMenu)
        let selectCleanupModelBody = try Self.functionBody(named: "selectCleanupModel", in: cleanupMenu)

        #expect(menuBuilder.contains(#""Cleanup Model: \(CleanupModelCatalog.displayName(for: modelId))""#))
        #expect(menuBuilder.contains("selectedModel: modelId"))
        #expect(modelMenuBody.contains("CleanupModelCatalog.options"))
        #expect(modelMenuBody.contains("item.representedObject = option"))
        #expect(modelMenuBody.contains("item.state = option.id == selectedModel ? .on : .off"))
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
        let applyBody = try Self.functionBody(named: "applyCleanupModel", in: delegate)

        #expect(selectBody.contains("applyCleanupModel(option.id)"))

        for forbidden in ["retrySetup", "startPipeline", "prepareModelGate", "showModelLoadingState"] {
            #expect(!applyBody.contains(forbidden),
                    "changing the cleanup model must not \(forbidden): that re-warms ASR and shows the loading pulse")
        }
        #expect(applyBody.contains("updateCleanupConfig"),
                "the cleanup-model change must apply live to the running orchestrator")
        #expect(orchestrator.contains("func updateCleanupConfig"),
                "the orchestrator must expose a live cleanup-config update so no rebuild is needed")
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
        // The settle-to-idle sequence is shared by key-up and the silent cancel, so
        // it lives in settleToIdle rather than inline in the sequencer closure.
        let settleToIdleBody = try Self.functionBody(named: "settleToIdle", in: delegate)

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
        #expect(Self.statementCount(#"isPipelineActive\s*=\s*false"#, in: settleToIdleBody) == 1)
        #expect(Self.containsInOrder([
            "self?.isPipelineActive = true",
            "self?.didShowPipelineStatus = false",
        ], in: startPipelineBody))
        // Sliced per switch arm: a whole-body ordered search stays green when the
        // .cancel arm loses its settle call or the .up arm settles before draining,
        // because the sibling arm still supplies a drain→settle pair.
        let upArm = try Self.slice(of: startPipelineBody, from: "case .up(let mode):", to: "case .cancel:")
        let cancelArm = try Self.slice(of: startPipelineBody, from: "case .cancel:")
        // Sensitivity: reorder settle before drain in the .up arm → RED.
        #expect(Self.containsInOrder([
            "orchestrator.handle(.stopRequested(",
            "awaitPipelineDrain()",
            "self?.settleToIdle()",
        ], in: upArm),
        "key-up must stop, drain the pipeline, then settle to idle — in that order")
        // Sensitivity: delete settleToIdle() from the .cancel arm → RED.
        #expect(Self.containsInOrder([
            "orchestrator.handle(.cancelRequested)",
            "awaitPipelineDrain()",
            "self?.settleToIdle()",
        ], in: cancelArm),
        "a silent cancel must cancel, drain the pipeline, then settle to idle — in that order")
        // Presence-only for the two independent if-guards (their relative order and
        // negation spelling are free). Sensitivity: set the idle glyph or the Idle
        // title unconditionally (drop either guard) → its flag vanishes → RED.
        #expect(Self.containsInOrder(["if", "isShowingSadToFailStatus", "setStatusGlyph(.idle"], in: settleToIdleBody),
                "the idle glyph must stay guarded by the sad-to-fail flag")
        #expect(Self.containsInOrder(["if", "didShowPipelineStatus", #"title = "Idle""#], in: settleToIdleBody),
                "the Idle title must stay guarded by the shown-pipeline-status flag")
    }

    /// The live status line renders the bare state word: the "Status:" prefix was
    /// dropped at every render site so it reads without a redundant label. The
    /// prefix is set at roughly nine sites across these two app-target files
    /// (recording, processing, idle, setup / hotkey-setup required, the
    /// preparing-model pulse), only one of which the settle-to-idle guard above
    /// pins by position — so a whole-file negative assert is what stops the prefix
    /// creeping back into any unguarded site. Mirrors the DictationMenuBuilder
    /// prefix guard. `code(_:)` strips comments (but keeps string literals), so a
    /// future comment naming the old prefix cannot false-trip this.
    /// Stated sensitivity: reintroduce `"Status: Idle"` in the model-gate file, or
    /// `"Status: Recording"` in AppDelegate, → the matching `#expect` goes RED.
    @Test
    func statusTitlesCarryNoRedundantPrefix() throws {
        let delegate = try Self.code("Sources/slovo/AppDelegate.swift")
        let modelGate = try Self.code("Sources/slovo/AppDelegate+ModelGate.swift")
        #expect(!delegate.contains("Status: "))
        #expect(!modelGate.contains("Status: "))
    }

    /// AC10: the dropdown's "Mute Audio While Dictating" switch renders as a
    /// checkmark toggle wired to the AppDelegate selector. The builder lives in the
    /// app target (not unit-importable), so this scans its source.
    /// Stated sensitivity: drop the `state = isOn ? .on : .off` checkmark, the
    /// "Mute Audio While Dictating" title, or the
    /// `#selector(AppDelegate.toggleMuteWhileDictating` action wiring → the matching
    /// `#expect` goes RED.
    @Test
    func menuBuilderRendersMuteWhileDictatingCheckmarkToggle() throws {
        let builder = try Self.code("Sources/slovo/DictationMenuBuilder.swift")

        #expect(builder.contains("Mute Audio While Dictating"),
                "the switch must carry its user-visible title")
        #expect(builder.contains("state = isOn ? .on : .off"),
                "the switch must render its persisted state as a checkmark")
        #expect(builder.contains("#selector(AppDelegate.toggleMuteWhileDictating"),
                "the switch must be wired to the AppDelegate toggle selector")
    }

    /// AC11: the mute-while-dictating switch applies live to the NEXT dictation
    /// without a pipeline rebuild — mirroring the cleanup-model change (#2). It must
    /// push the flag to the running orchestrator and refresh the menu, never re-warm
    /// ASR; and `makeMenu` must feed the builder the REAL persisted flag.
    /// Stated sensitivity: route the change through a rebuild
    /// (retrySetup/startPipeline/prepareModelGate/showModelLoadingState), drop the
    /// live orchestrator update, or hard-code the menu flag instead of reading config
    /// → the matching `#expect` goes RED.
    @Test
    func changingMuteWhileDictatingAppliesLiveWithoutPipelineRebuild() throws {
        let delegate = try Self.code("Sources/slovo/AppDelegate.swift")
        let orchestrator = try Self.code("Sources/SlovoCore/Orchestrator.swift")
        let applyBody = try Self.functionBody(named: "applyMuteWhileDictating", in: delegate)
        let toggleBody = try Self.functionBody(named: "toggleMuteWhileDictating", in: delegate)
        let makeMenuBody = try Self.functionBody(named: "makeMenu", in: delegate)

        for forbidden in ["retrySetup", "startPipeline", "prepareModelGate", "showModelLoadingState"] {
            #expect(!applyBody.contains(forbidden),
                    "changing the mute switch must not \(forbidden): that re-warms ASR and shows the loading pulse")
        }
        #expect(applyBody.contains("updateMutesSystemAudioWhileDictating"),
                "the mute-switch change must apply live to the running orchestrator")
        #expect(applyBody.contains("installStatusMenu"),
                "the mute switch is menu-visible, so its change must rebuild the status menu")
        #expect(toggleBody.contains("applyMuteWhileDictating"),
                "the @objc toggle selector must route through the live-apply path")
        #expect(makeMenuBody.contains("mutesSystemAudioWhileDictating: config.mutesSystemAudioWhileDictating"),
                "makeMenu must feed the builder the REAL persisted flag, not a literal")
        #expect(orchestrator.contains("func updateMutesSystemAudioWhileDictating"),
                "the orchestrator must expose a live mute-flag update so no rebuild is needed")
    }

    /// AC12: the FSM stays PURE — `transition` decides on (state, event) only. The
    /// mute switch is a CAPTURE-stage flag applied in the orchestrator, never
    /// threaded into the pure decision table.
    /// Stated sensitivity: add a config/mute parameter to `transition` (thread the
    /// live flag into the FSM) → the signature grows that parameter → RED. This is a
    /// stays-green purity guard; it is green today because the FSM is already pure.
    @Test
    func fsmTransitionSignatureTakesNoConfigParameter() throws {
        let fsm = try Self.code("Sources/SlovoCore/FSM/DictationFsm.swift")
        let signature = try Self.slice(of: fsm, from: "func transition(", to: ")")

        #expect(signature.contains("_ state:"), "the pure FSM must still switch on the current state")
        #expect(signature.contains("on event:"), "the pure FSM must still switch on the incoming event")
        for forbidden in ["config", "Config", "mutes", "muteWhile"] {
            #expect(!signature.contains(forbidden),
                    "the pure FSM transition must not take a \(forbidden) parameter")
        }
    }
}
