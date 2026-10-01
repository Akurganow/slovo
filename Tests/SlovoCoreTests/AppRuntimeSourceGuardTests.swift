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

    /// The composition root must derive the database passphrase from THIS
    /// Mac's hardware identity. A hardcoded literal here would share one key
    /// across every installation and still pass the whole behavioral suite,
    /// which drives `open` with explicit test passphrases — this line is the
    /// only pin on the production wiring.
    /// Stated sensitivity: replace the argument with any literal provider →
    /// RED.
    @Test
    func compositionDerivesTheDatabasePassphraseFromHardwareIdentity() throws {
        let composition = try Self.code("Sources/slovo/AppComposition.swift")

        #expect(composition.contains("passphrase: PersonalizationDatabasePassphrase.derive"))
    }

    @Test
    func readinessCheckUsesKeyPresenceWithoutDecryptingSecret() throws {
        let composition = try Self.code("Sources/slovo/AppComposition.swift")
        let keyProvider = try Self.code("Sources/SlovoCore/Cleaner/KeychainAPIKeyProvider.swift")
        let makeLiveBody = try Self.functionBody(named: "makeLive", in: composition)
        let hasConfiguredKeyBody = try Self.functionBody(named: "hasConfiguredKey", in: keyProvider)
        let keychainItemExistsBody = try Self.functionBody(named: "keychainItemExists", in: keyProvider)

        #expect(makeLiveBody.contains("FirstRunFlow.pendingSteps("))
        // Stated sensitivity: read key presence in makeLive again, or the
        // secret through apiKey() → RED.
        #expect(!makeLiveBody.contains("hasConfiguredKey"),
                "the composition takes key presence from the state it is handed, never from the Keychain")
        #expect(!Self.withoutStringLiterals(makeLiveBody).contains("apiKey()"))
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

    /// The launch boundary as AMENDED by the key-scope change (spec §9.1): nothing
    /// BEFORE `hotkeyMonitor.start()` may read the Keychain SECRET — the pipeline
    /// must become usable without a cleanup key, and without a Keychain prompt
    /// racing the hotkey tap. What the amendment adds is that the post-start scope
    /// fetch MAY read it: the fetcher carries the key, and it is reached only from
    /// the events ordered after the start call (pinned by
    /// `scopeEventsFireOnlyAfterHotkeyStart` below).
    /// Stated sensitivity: preload/decrypt the key on the pre-start path → RED.
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

    // K10 ordering (spec §9.1): the scope event — and therefore the first possible
    // Keychain-secret read via the fetcher — sits strictly AFTER hotkey start, and
    // INSIDE the do block (the catch/recovery path must not fire it). The fetch gate
    // itself is the reducer's (`launchFetchWaitsForPipelineStart`).
    // Stated sensitivity: move `applyScope(.pipelineStarted)` above
    // `hotkeyMonitor.start()` or below the catch → RED; call `startStoreEffects()`
    // before `statusItem = item` or after `startPipeline()` → RED.
    @Test
    func scopeEventsFireOnlyAfterHotkeyStart() throws {
        let app = try Self.code("Sources/slovo/AppDelegate.swift")
        let body = try Self.functionBody(named: "startPipeline", in: app)
        let hotkey = try #require(body.range(of: "hotkeyMonitor.start()"))
        let started = try #require(body.range(of: "applyScope(.pipelineStarted)"))
        let catchMark = try #require(body.range(of: "} catch"))
        #expect(hotkey.lowerBound < started.lowerBound)
        #expect(started.lowerBound < catchMark.lowerBound)
        // The menu subscriber's first build needs the status item, and must land
        // before startPipeline can install an onboarding menu.
        let launch = try Self.functionBody(named: "applicationDidFinishLaunching", in: app)
        #expect(Self.containsInOrder(["statusItem = item", "startStoreEffects()", "startPipeline()"], in: launch))
    }

    // The scope fetch has one call site in the app target: the target closure the
    // store's fetch subscriber runs for a pending generation (K10/§9.1).
    // `AppState.cleanupScope` is `private(set)`, so the compiler, not this guard,
    // keeps `applyScope` its only writer.
    // Stated sensitivity: a second `fetchScopeIds(` call in Sources/slovo, or
    // dropping either K8 wiring line → RED; a config write in `scopeFailureObserver`
    // → RED.
    @Test
    func scopeFetchAndFailureFeedAreWiredOnce() throws {
        var fetchCallCount = 0
        for file in try Self.swiftSourceFiles(under: "Sources/slovo") {
            fetchCallCount += try Self.code(file).components(separatedBy: "fetchScopeIds(").count - 1
        }
        #expect(fetchCallCount == 1)
        // K8 chain, links (b) and (c) — the v5-verification's G1: without these,
        // dropping either wiring line leaves every suite green while the 404
        // self-heal never fires. Link (a) is pinned beside the seam's tests.
        let composition = try Self.code("Sources/slovo/AppComposition.swift")
        #expect(composition.contains("dependencies.onCleanupFailure = onCleanupFailure"))
        let delegate = try Self.code("Sources/slovo/AppDelegate.swift")
        #expect(delegate.contains("onCleanupFailure: scopeFailureObserver()"))
        // K1, app half: the scope failure feed never writes config. The SlovoCore half
        // is AppStateTests.applyScopeNeverWritesConfig and the fetch effect test.
        let scopeWiring = try Self.code("Sources/slovo/AppDelegate+CleanupScope.swift")
        #expect(!scopeWiring.contains(".config."), "the scope failure feed must never write config (K1)")
    }

    // K4's "NEVER on the key-up path": the dictation-side core never references
    // the scope machinery — the only SlovoCore→app channel is the K8 observer,
    // which hops to the main actor after the failure is already degraded.
    // Sensitivity: reference the reducer or fetcher from the orchestrator/FSM → RED.
    @Test
    func hotPathNeverTouchesTheScopeMachinery() throws {
        for file in ["Sources/SlovoCore/Orchestrator.swift", "Sources/SlovoCore/FSM/DictationFsm.swift"] {
            let source = try Self.code(file)
            #expect(!source.contains("CleanupScopeReducer"))
            #expect(!source.contains("OpenRouterModelScopeFetcher"))
            #expect(!source.contains("applyScope("))
        }
    }

    /// The store is the app's one copy of `Config`: `AppDelegate.init` seeds it from
    /// UserDefaults once, and the persistence subscriber in SlovoCore is the only
    /// writer back. The app target has no test seam, so this reads its source.
    /// Stated sensitivity: an app writer that saves on its own, or a reader that
    /// decodes UserDefaults again → RED.
    @Test
    func appTargetLoadsConfigOnceAndNeverSaves() throws {
        var loads = 0
        var saves = 0
        for file in try Self.swiftSourceFiles(under: "Sources/slovo") {
            let source = try Self.code(file)
            loads += source.components(separatedBy: "ConfigStore.load(").count - 1
            saves += source.components(separatedBy: "ConfigStore.save(").count - 1
        }
        #expect(loads == 1, "only the store seed may decode UserDefaults; found \(loads) reads")
        #expect(saves == 0, "only the store's persistence subscriber may save Config; found \(saves) app-side saves")
    }

    /// Every orchestrator push is a store subscriber in SlovoCore, so the app target
    /// pushes nothing itself.
    /// Stated sensitivity: an app-side push beside the store wiring → RED.
    @Test
    func appTargetPushesNothingToTheOrchestrator() throws {
        let pushes = [
            "updateCleanupConfig(", "updateMutesSystemAudioWhileDictating(",
            "updateUsesVocabularyBias(", "updateRecognitionLanguage(",
        ]
        for file in try Self.swiftSourceFiles(under: "Sources/slovo") {
            let source = try Self.code(file)
            for push in pushes {
                #expect(!source.contains(push), "\(file) pushes \(push) beside the store wiring")
            }
        }
    }

    /// Stated sensitivity: build the submenu from the catalog instead of the
    /// `options` parameter, or write anything but the chosen id → RED.
    @Test
    func appMenuSelectsOpenRouterModelAndShowsCurrentModel() throws {
        let cleanupMenu = try Self.code("Sources/slovo/AppDelegate+CleanupMenu.swift")
        let menuBuilder = try Self.code("Sources/slovo/DictationMenuBuilder.swift")
        let modelMenuBody = try Self.functionBody(named: "modelMenu", in: cleanupMenu)
        let selectCleanupModelBody = try Self.functionBody(named: "selectCleanupModel", in: cleanupMenu)

        #expect(menuBuilder.contains(#""Cleanup Model: \(CleanupModelCatalog.displayName(for: modelId))""#))
        #expect(menuBuilder.contains("selectedModel: modelId"))
        #expect(modelMenuBody.contains("for option in options"))
        #expect(modelMenuBody.contains("item.representedObject = option"))
        #expect(modelMenuBody.contains("item.state = option.id == selectedModel ? .on : .off"))
        #expect(selectCleanupModelBody.contains("sender.representedObject as? CleanupModelOption"))
        #expect(selectCleanupModelBody.contains("$0.config.openRouterModel = option.id"))
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
        let speechModel = try #require(sourceByPath["Sources/SlovoCore/ASR/SharedSpeechModel.swift"])
        let engine = try #require(sourceByPath["Sources/SlovoCore/ASR/WhisperKitEngine.swift"])

        #expect(speechModel.contains("WhisperKitTranscriber("))
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
        // The brief self-clearing glyph (sad-to-fail and empty-result) lives in the
        // shared flashBriefStatusGlyph helper, so its self-clear is pinned there.
        let flashBriefStatusGlyphBody = try Self.functionBody(named: "flashBriefStatusGlyph", in: delegate)

        #expect(!StatusMessage.preparingSpeechModel.isPersistentNotice)
        #expect(StatusMessage.cleanupUnavailableInsertedAsSpoken.isSadToFailNotice)
        #expect(!StatusMessage.cleanupUnavailableInsertedAsSpoken.isPersistentNotice)
        // The gate lets only real notices through — each transient/persistent notice
        // kind plus the active pipeline. Sensitivity: drop any disjunct → RED.
        #expect(Self.containsInOrder([
            "guard status.isPersistentNotice",
            "|| status.isSadToFailNotice",
            "|| status.isNoSpeechNotice",
            "|| isPipelineActive else {",
        ], in: showStatusBody))
        #expect(Self.containsInOrder([
            "if status.isPersistentNotice",
            "didShowPipelineStatus = true",
            "statusTextItem?.title",
        ], in: showStatusBody))
        // The sad-to-fail status routes to the shared brief-glyph flash, which paints
        // the glyph and schedules its self-clear back to idle after the brief window —
        // so the degradation notice cannot stick. Sensitivity: drop the sad-to-fail
        // route to flashBriefStatusGlyph, or the helper's timed reset → RED.
        #expect(Self.containsInOrder([
            "if status.isSadToFailNotice",
            "flashBriefStatusGlyph(status)",
        ], in: showStatusBody))
        #expect(Self.containsInOrder([
            "setStatusGlyph(status",
            "Task { @MainActor",
            "try? await Task.sleep(for: .seconds(1))",
            "paintIdleGlyph",
        ], in: flashBriefStatusGlyphBody))
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
        // negation spelling are free). Sensitivity: set the idle glyph or the idle
        // title unconditionally (drop either guard) → its flag vanishes → RED.
        #expect(Self.containsInOrder(["if", "isShowingBriefStatus", "paintIdleGlyph"], in: settleToIdleBody),
                "the idle glyph must stay guarded by the brief-status flag")
        #expect(Self.containsInOrder(["if", "didShowPipelineStatus", "title = idleStatusTitle"], in: settleToIdleBody),
                "the idle title must stay guarded by the shown-pipeline-status flag")
    }

    /// The live status line renders the bare state word, with no "Status:" prefix,
    /// so it reads without a redundant label. The status line is set at roughly
    /// nine sites across these two app-target files (recording, processing, idle,
    /// setup / hotkey-setup required, the preparing-model pulse), only one of
    /// which the settle-to-idle guard above pins by position — so a whole-file
    /// negative assert is what stops the prefix creeping back into any unguarded
    /// site. Mirrors the DictationMenuBuilder prefix guard. `code(_:)` strips
    /// comments (but keeps string literals), so a future comment naming the
    /// prefix cannot false-trip this.
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
    /// without a pipeline rebuild. The toggle writes the store; the push is the
    /// store's subscriber (`AppStoreEffectsTests.muteAndBiasReachTheOrchestrator`).
    /// Stated sensitivity: route the toggle through a rebuild
    /// (retrySetup/startPipeline/prepareModelGate/showModelLoadingState), write
    /// anything but the toggled field, or hard-code the builder's menu flag → RED.
    @Test
    func changingMuteWhileDictatingAppliesLiveWithoutPipelineRebuild() throws {
        let delegate = try Self.code("Sources/slovo/AppDelegate.swift")
        let builder = try Self.code("Sources/slovo/DictationMenuBuilder.swift")
        let toggleBody = try Self.functionBody(named: "toggleMuteWhileDictating", in: delegate)

        for forbidden in ["retrySetup", "startPipeline", "prepareModelGate", "showModelLoadingState"] {
            #expect(!toggleBody.contains(forbidden),
                    "changing the mute switch must not \(forbidden): that re-warms ASR and shows the loading pulse")
        }
        #expect(toggleBody.contains("$0.config.mutesSystemAudioWhileDictating.toggle()"),
                "the @objc toggle selector must flip the stored switch through the store")
        #expect(builder.contains("mutesSystemAudioWhileDictating: input.mutesSystemAudioWhileDictating"),
                "the builder must feed the menu model the value from its input, not a literal")
    }

    /// The session factory must feed the pure `decodingOptions` the session's OWN
    /// terms and the loaded model's OWN tokenizer. The hermetic unit test pins the
    /// function; this pins the CALL into it, where a build that never biases anything
    /// (empty terms, or a tokenizer closure that always yields nothing) would
    /// otherwise leave every test green — the false-green shape this repo has already
    /// been burned by, one floor up.
    /// Stated sensitivity: pass `biasTerms: []`, hand it `{ _ in [] }` instead of
    /// the engine's tokenizer, or decode a literal language (`language: .auto`)
    /// instead of the session's own → the matching `#expect` goes RED. Each token
    /// appears exactly once in the file, inside this call.
    @Test
    func speechSessionFactoryFeedsDecodingOptionsItsTermsAndTokenizer() throws {
        let engine = try Self.code("Sources/SlovoCore/ASR/WhisperKitEngine.swift")
        let factoryBody = try Self.functionBody(named: "makeSpeechStreamingSession", in: engine)

        #expect(factoryBody.contains("biasTerms: biasTerms"),
                "the session's own terms must reach the decoding options, not a literal")
        #expect(factoryBody.contains("language: language"),
                "the session's own language must reach the decoding options, not a literal")
        #expect(factoryBody.contains("engine.tokenizer?.encode(text: text)"),
                "the loaded model's tokenizer must measure the prompt, not a stub closure")
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
