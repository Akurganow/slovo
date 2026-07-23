import AppKit
import Settings
import SlovoCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let logger: Logger
    let defaults: UserDefaults
    /// Key presence is an APP fact, not a pipeline fact: the app owns the provider
    /// and injects it into the pipeline, so has-key / save-key / cleanup
    /// availability never depend on whether the pipeline composite exists yet.
    let openRouterKeyProvider = KeychainOpenRouterKeyProvider()
    var statusItem: NSStatusItem?
    var statusTextItem: NSMenuItem?
    var composition: AppComposition.Live?
    var settingsWindowController: SettingsWindowController?
    // Internal (not private) so the AppDelegate+About extension in its own file can
    // reach the cached window; a repeat click must focus it, not open a second one.
    var aboutWindow: AboutWindow?
    private var vocabularyQuickAddWindow: VocabularyQuickAddWindow?
    private var didShowPipelineStatus = false
    var isPipelineActive = false
    var isShowingSadToFailStatus = false
    var isModelReady = false
    private var onboardingSteps: [OnboardingStep] = []
    private var sadToFailResetTask: Task<Void, Never>?
    // Sibling of sadToFailResetTask: the pending reset of the update-install-failure
    // glyph flash, cancelled before a new flash so overlaps don't stack.
    var updateFailureResetTask: Task<Void, Never>?
    private var hotkeyEdgeSequencer: HotkeyEdgeSequencer?
    private var isRebuildingPipeline = false
    // Strong reference is load-bearing: Sparkle holds the updater and user-driver
    // delegates weakly, so the coordinator would deallocate without this.
    var updaterCoordinator: UpdaterCoordinator?
    // The one persistent update-line item, built by DictationMenuBuilder and mutated
    // in place by the update renderer; never rebuilt on a transition.
    var updateMenuItem: NSMenuItem?
    // True only while the onboarding menu is shown, so the dictation dropdown's
    // shared menu delegate never triggers the onboarding refresh on open.
    private var isPresentingOnboarding = false

    init(logger: Logger, defaults: UserDefaults = .standard) {
        self.logger = logger
        self.defaults = defaults
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setStatusGlyph(.idle, on: item.button)
        item.menu = makeMenu()
        statusItem = item

        startPipeline()
        startUpdater()
        logger.info("menu bar app ready")
    }

    private func makeMenu() -> NSMenu {
        let config = ConfigStore.load(from: defaults)
        let built = DictationMenuBuilder(target: self).make(
            trigger: config.trigger,
            selectedModelId: config.openRouterModel,
            mutesSystemAudioWhileDictating: config.mutesSystemAudioWhileDictating,
            translationLanguage: config.translationTargetLanguage.rawValue,
            cleanupAvailability: currentCleanupAvailability()
        )
        statusTextItem = built.statusItem
        // Sync the freshly built update row to the current state, so a rebuild while
        // an update is downloading or ready shows the right line immediately.
        if let indication = updaterCoordinator?.currentIndication {
            renderUpdateIndication(indication)
        }
        return built.menu
    }

    private func startPipeline() {
        do {
            let live = try AppComposition.makeLive(
                defaults: defaults,
                openRouterKeyProvider: openRouterKeyProvider,
                statusReporter: { [weak self] status in
                    Task { @MainActor [weak self] in
                        self?.showStatus(status)
                    }
                }
            )
            composition = live
            guard live.onboardingSteps == [.ready] else {
                presentOnboarding(live.onboardingSteps)
                logger.info("onboarding pending")
                return
            }
            isPresentingOnboarding = false
            prepareModelGate(for: live)
            let sequencer = HotkeyEdgeSequencer { [weak self, orchestrator = live.orchestrator] phase in
                switch phase {
                case .down(let mode): guard await MainActor.run(body: { self?.isModelReady == true })
                    else { return await MainActor.run { self?.showModelLoadingState() } }
                    await MainActor.run {
                        self?.isPipelineActive = true
                        self?.didShowPipelineStatus = false
                        // The recording glyph is the semantic family (raw Ⰳ when
                        // cleanup is off — a translate hold cannot run there, though
                        // the hotkey core still latches — clean Ⱍ for a plain hold,
                        // translate Ⱂ for a Control latch), derived from the live
                        // availability inside applyRecordingGlyph.
                        self?.applyRecordingGlyph(mode)
                        self?.statusTextItem?.title = "Recording"
                    }
                    await orchestrator.handle(.startRequested)
                case .translateLatched:
                    guard await MainActor.run(body: { self?.isPipelineActive == true }) else { return }
                    await MainActor.run { self?.applyRecordingGlyph(.translate) }
                case .up(let mode): guard await MainActor.run(body: { self?.isPipelineActive == true }) else { return }
                    await MainActor.run {
                        self?.setStatusGlyph(.processing, on: self?.statusItem?.button)
                        if self?.didShowPipelineStatus == false {
                            self?.statusTextItem?.title = "Processing"
                        }
                    }
                    await orchestrator.handle(.stopRequested(mode))
                    await orchestrator.awaitPipelineDrain()
                    await MainActor.run { self?.settleToIdle() }
                case .cancel:
                    guard await MainActor.run(body: { self?.isPipelineActive == true }) else { return }
                    await orchestrator.handle(.cancelRequested)
                    await orchestrator.awaitPipelineDrain()
                    await MainActor.run { self?.settleToIdle() }
                }
            }
            hotkeyEdgeSequencer = sequencer
            live.hotkeyMonitor.onTrigger = { phase in
                sequencer.send(phase)
            }
            do {
                try live.hotkeyMonitor.start()
                logger.info("production composition started")
            } catch {
                presentHotkeyRecovery()
                logger.error("hotkey monitor failed")
            }
        } catch {
            logger.error("production composition failed")
        }
    }

    /// Derives and paints the recording glyph for a session's mode from the LIVE
    /// cleanup availability. The availability is read exactly once — here, as the
    /// derivation argument — so no sequencer arm carries a separate gate read that a
    /// mutant could leave dead while still running the paint; both arms share this.
    func applyRecordingGlyph(_ mode: DictationMode) {
        let glyphMode = MenuBarGlyph.recordingGlyphMode(mode: mode, isCleanupOn: currentCleanupAvailability().isOn)
        setStatusGlyph(recording: glyphMode, on: statusItem?.button)
    }

    /// Return the menu-bar glyph and status text to Idle when a session settles
    /// (normal stop or a silent cancel), leaving a sad-to-fail notice or an
    /// already-shown pipeline status untouched.
    private func settleToIdle() {
        isPipelineActive = false
        if !isShowingSadToFailStatus {
            setStatusGlyph(.idle, on: statusItem?.button)
        }
        if !didShowPipelineStatus {
            statusTextItem?.title = "Idle"
        }
    }

    private func presentOnboarding(_ steps: [OnboardingStep]) {
        // Setup surfaces through the menu-bar status and the onboarding menu only —
        // no modal alert. Permissions are requested from that menu, which triggers
        // the system prompts (menu-bar-only UX). The old per-permission "Continue
        // Setup" dialog re-appeared once for each permission because its dedup keyed
        // on the shrinking set of still-pending steps.
        onboardingSteps = steps
        isPresentingOnboarding = true
        statusTextItem?.title = "Setup Required"
        statusItem?.menu = makeOnboardingMenu(for: steps)
    }

    private func makeOnboardingMenu(for steps: [OnboardingStep]) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "Slovo Setup Required", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        if steps.contains(.requestMicrophone) {
            menu.addItem(actionItem("Request Microphone Access", #selector(openMicrophoneSettings)))
        }
        if steps.contains(.requestAccessibility) {
            menu.addItem(actionItem("Request Accessibility Access", #selector(openAccessibilitySettings)))
        }
        menu.addItem(.separator())
        menu.addItem(actionItem("Retry Setup", #selector(retrySetup)))
        menu.addItem(NSMenuItem(title: "Quit Slovo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func presentHotkeyRecovery() {
        statusTextItem?.title = "Hotkey Setup Required"
        statusItem?.menu = makeHotkeyRecoveryMenu()
    }

    private func makeHotkeyRecoveryMenu() -> NSMenu {
        let menu = NSMenu()
        let title = NSMenuItem(title: "Slovo Hotkey Setup Required", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(actionItem("Request Input Monitoring Access", #selector(openInputMonitoringSettings)))
        menu.addItem(.separator())
        menu.addItem(actionItem("Retry Setup", #selector(retrySetup)))
        menu.addItem(NSMenuItem(title: "Quit Slovo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // The dictation dropdown shares this delegate; only the onboarding menu
        // wants the pending-permission refresh.
        guard isPresentingOnboarding else { return }
        refreshOnboardingMenuIfNeeded()
    }

    private func refreshOnboardingMenuIfNeeded() {
        let latestSteps = FirstRunFlow.pendingSteps(permissions: SystemPermissionPreflighter().preflight())
        guard latestSteps != onboardingSteps else { return }
        onboardingSteps = latestSteps
        if latestSteps == [.ready] {
            retrySetup()
        } else {
            statusItem?.menu = makeOnboardingMenu(for: latestSteps)
        }
    }

    func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func showStatus(_ status: StatusMessage) {
        guard status.isPersistentNotice || status.isSadToFailNotice || isPipelineActive else {
            return
        }
        if status.isPersistentNotice {
            didShowPipelineStatus = true
        }
        if status.isSadToFailNotice {
            didShowPipelineStatus = true
            isShowingSadToFailStatus = true
            setStatusGlyph(status: status, on: statusItem?.button)
            sadToFailResetTask?.cancel()
            sadToFailResetTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.isShowingSadToFailStatus = false
                self?.setStatusGlyph(.idle, on: self?.statusItem?.button)
                if self?.isPipelineActive == false {
                    self?.statusTextItem?.title = "Idle"
                }
            }
        }
        statusTextItem?.title = Self.title(for: status)
    }

    @objc
    private func openMicrophoneSettings() {
        Task { @MainActor in
            await requestPermission(.microphone, fallbackPane: "Privacy_Microphone")
        }
    }

    @objc
    private func openAccessibilitySettings() {
        Task { @MainActor in
            await requestPermission(.accessibility, fallbackPane: "Privacy_Accessibility")
        }
    }

    @objc
    private func openInputMonitoringSettings() {
        Task { @MainActor in
            await requestPermission(.inputMonitoring, fallbackPane: "Privacy_ListenEvent")
        }
    }

    @objc
    func showVocabularyQuickAdd() {
        if vocabularyQuickAddWindow == nil {
            vocabularyQuickAddWindow = VocabularyQuickAddWindow(onAdd: { [weak self] terms in
                self?.addVocabulary(terms)
            })
        }
        vocabularyQuickAddWindow?.show()
    }

    // Internal (not private) so the AppDelegate+Settings extension can call it
    // for the honest ASR rebuild on a recognition-language change.
    @objc
    func retrySetup() {
        // A rebuild is asynchronous (it joins the previous edge consumer first); a
        // second retry arriving before it finishes must not spawn a parallel
        // teardown+rebuild that could leave a mismatched sequencer and composition.
        guard !isRebuildingPipeline else { return }
        isRebuildingPipeline = true
        composition?.hotkeyMonitor.stop()
        installStatusMenu()
        // Join the previous edge consumer before a new one is built, so a rebuilt
        // monitor cannot leave two consumers double-handling the same fn edges.
        let previousSequencer = hotkeyEdgeSequencer
        Task { @MainActor in
            await previousSequencer?.stop()
            // startPipeline() through isRebuildingPipeline = false must stay synchronous: an
            // await here could let a rapid language change persist to Config after the read
            // yet drop its own retry via the guard above, pinning a stale language.
            startPipeline()
            isRebuildingPipeline = false
        }
    }

    private func openSettingsPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func requestPermission(_ permission: SystemPermission, fallbackPane: String) async {
        guard let permissionRequester = composition?.permissionRequester else {
            openSettingsPane(fallbackPane)
            return
        }
        let granted = await permissionRequester.request(permission)
        if granted {
            retrySetup()
        } else {
            openSettingsPane(fallbackPane)
        }
    }

    /// Rebuilds and reinstalls the status-bar dropdown, re-capturing the live
    /// status item. Called after a settings change that alters a menu-visible value
    /// (the hotkey hint or the selected cleanup model).
    func installStatusMenu() {
        statusItem?.menu = makeMenu()
    }

    /// Persists a cleanup-model change and applies it to the NEXT dictation live.
    /// Unlike `retrySetup`, this does NOT rebuild the pipeline: the resident ASR
    /// model is never re-warmed and the "Preparing Speech Model" loading pulse
    /// never appears for a change that only swaps the cleanup LLM id (#2). The menu
    /// is refreshed so the selected-model checkmark tracks the new choice.
    func applyCleanupModel(_ modelId: String) {
        var config = ConfigStore.load(from: defaults)
        config.openRouterModel = modelId
        do {
            try ConfigStore.save(config, to: defaults)
        } catch {
            logger.error("config save failed")
            return
        }
        installStatusMenu()
        pushEffectiveCleanupConfig()
    }

    func currentCleanupAvailability() -> CleanupAvailability {
        CleanupAvailability.derive(
            preference: ConfigStore.load(from: defaults).cleanupEnabled,
            keyPresent: hasOpenRouterKey()
        )
    }

    /// The single push funnel (spec amendment A5): every mutation that can change
    /// the effective cleanup state — the toggle, a key save, any cleanup tunable —
    /// re-derives `preference && keyPresent` HERE and pushes exactly one
    /// CleanupConfig. No other call site may talk to updateCleanupConfig.
    func pushEffectiveCleanupConfig() {
        let config = ConfigStore.load(from: defaults)
        var cleanupConfig = config.cleanupConfig
        // The effective-on rule has ONE definition (CleanupAvailability.derive);
        // this site only CALLS it — never re-spell the predicate here.
        cleanupConfig.runsCleaner = CleanupAvailability.derive(
            preference: config.cleanupEnabled,
            keyPresent: hasOpenRouterKey()
        ).isOn
        Task { @MainActor in
            await composition?.orchestrator.updateCleanupConfig(cleanupConfig)
        }
    }

    /// Persists the preference and applies it to the NEXT dictation live — the
    /// applyMuteWhileDictating shape: no rebuild, no ASR re-warm; the menu is
    /// rebuilt for the checkmark and the translate submenu's enabled state.
    func applyCleanupEnabled(_ enabled: Bool) {
        var config = ConfigStore.load(from: defaults)
        config.cleanupEnabled = enabled
        do {
            try ConfigStore.save(config, to: defaults)
        } catch {
            logger.error("config save failed")
            return
        }
        installStatusMenu()
        pushEffectiveCleanupConfig()
    }

    @objc
    func toggleCleanupDictation(_ sender: NSMenuItem) {
        applyCleanupEnabled(!ConfigStore.load(from: defaults).cleanupEnabled)
    }

    /// Persists a mute-while-dictating change and applies it to the NEXT dictation
    /// live. Like `applyCleanupModel`, this does NOT rebuild the pipeline: the
    /// resident ASR model is never re-warmed and no loading pulse appears for a
    /// change that only flips a capture-stage flag. The switch is menu-visible, so
    /// the status menu is rebuilt to track the checkmark.
    func applyMuteWhileDictating(_ enabled: Bool) {
        var config = ConfigStore.load(from: defaults)
        config.mutesSystemAudioWhileDictating = enabled
        do {
            try ConfigStore.save(config, to: defaults)
        } catch {
            logger.error("config save failed")
            return
        }
        installStatusMenu()
        Task { @MainActor in
            await composition?.orchestrator.updateMutesSystemAudioWhileDictating(enabled)
        }
    }

    @objc
    func toggleMuteWhileDictating(_ sender: NSMenuItem) {
        let config = ConfigStore.load(from: defaults)
        applyMuteWhileDictating(!config.mutesSystemAudioWhileDictating)
    }

    private static func title(for step: OnboardingStep) -> String {
        switch step {
        case .requestMicrophone:
            return "Microphone permission"
        case .requestAccessibility:
            return "Accessibility permission"
        case .ready:
            return "Ready"
        }
    }
}
