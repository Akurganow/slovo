import AppKit
import Settings
import SlovoCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let logger: Logger
    let defaults: UserDefaults
    var statusItem: NSStatusItem?
    var statusTextItem: NSMenuItem?
    var composition: AppComposition.Live?
    var settingsWindowController: SettingsWindowController?
    private var vocabularyQuickAddWindow: VocabularyQuickAddWindow?
    private var didShowPipelineStatus = false
    var isPipelineActive = false
    var isShowingSadToFailStatus = false
    var isModelReady = false
    private var onboardingSteps: [OnboardingStep] = []
    private var sadToFailResetTask: Task<Void, Never>?
    private var hotkeyEdgeSequencer: HotkeyEdgeSequencer?
    private var isRebuildingPipeline = false

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
        logger.info("menu bar app ready")
    }

    private func makeMenu() -> NSMenu {
        let config = ConfigStore.load(from: defaults)
        let built = DictationMenuBuilder(target: self).make(
            trigger: config.trigger,
            selectedModelId: config.openRouterModel,
            mutesSystemAudioWhileDictating: config.mutesSystemAudioWhileDictating,
            translationLanguage: config.translationTargetLanguage.rawValue
        )
        statusTextItem = built.statusItem
        return built.menu
    }

    private func startPipeline() {
        do {
            let live = try AppComposition.makeLive(defaults: defaults, statusReporter: { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.showStatus(status)
                }
            })
            composition = live
            guard live.onboardingSteps == [.ready] else {
                presentOnboarding(live.onboardingSteps)
                logger.info("onboarding pending")
                return
            }
            prepareModelGate(for: live)
            let sequencer = HotkeyEdgeSequencer { [weak self, orchestrator = live.orchestrator] phase in
                switch phase {
                case .down: guard await MainActor.run(body: { self?.isModelReady == true })
                    else { return await MainActor.run { self?.showModelLoadingState() } }
                    await MainActor.run {
                        self?.isPipelineActive = true
                        self?.didShowPipelineStatus = false
                        self?.setStatusGlyph(.recording, on: self?.statusItem?.button)
                        self?.statusTextItem?.title = "Status: Recording"
                    }
                    await orchestrator.handle(.startRequested)
                case .up(let mode): guard await MainActor.run(body: { self?.isPipelineActive == true }) else { return }
                    await MainActor.run {
                        self?.setStatusGlyph(.processing, on: self?.statusItem?.button)
                        if self?.didShowPipelineStatus == false {
                            self?.statusTextItem?.title = "Status: Processing"
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

    /// Return the menu-bar glyph and status text to Idle when a session settles
    /// (normal stop or a silent cancel), leaving a sad-to-fail notice or an
    /// already-shown pipeline status untouched.
    private func settleToIdle() {
        isPipelineActive = false
        if !isShowingSadToFailStatus {
            setStatusGlyph(.idle, on: statusItem?.button)
        }
        if !didShowPipelineStatus {
            statusTextItem?.title = "Status: Idle"
        }
    }

    private func presentOnboarding(_ steps: [OnboardingStep]) {
        // Setup surfaces through the menu-bar status and the onboarding menu only —
        // no modal alert. Permissions are requested from that menu, which triggers
        // the system prompts (menu-bar-only UX). The old per-permission "Continue
        // Setup" dialog re-appeared once for each permission because its dedup keyed
        // on the shrinking set of still-pending steps.
        onboardingSteps = steps
        statusTextItem?.title = "Status: Setup Required"
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
        statusTextItem?.title = "Status: Hotkey Setup Required"
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
                    self?.statusTextItem?.title = "Status: Idle"
                }
            }
        }
        statusTextItem?.title = "Status: \(Self.title(for: status))"
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
        let cleanupConfig = config.cleanupConfig
        Task { @MainActor in
            await composition?.orchestrator.updateCleanupConfig(cleanupConfig)
        }
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

    /// Persists a translate-target change and applies it to the NEXT dictation live.
    /// Like `applyCleanupModel`, this does NOT rebuild the pipeline: the target only
    /// affects the cleanup prompt in translate mode, so the resident ASR model is
    /// never re-warmed and no loading pulse appears. The menu is refreshed so the
    /// selected-language checkmark and the "Translate to" title track the new choice.
    func applyTranslationLanguage(_ language: Language) {
        var config = ConfigStore.load(from: defaults)
        config.translationTargetLanguage = language
        do {
            try ConfigStore.save(config, to: defaults)
        } catch {
            logger.error("config save failed")
            return
        }
        installStatusMenu()
        let cleanupConfig = config.cleanupConfig
        Task { @MainActor in
            await composition?.orchestrator.updateCleanupConfig(cleanupConfig)
        }
    }

    /// Persists the spell-check hints toggle and applies it to the NEXT dictation
    /// live. Like `applyCleanupModel`, this does NOT rebuild the pipeline: the change
    /// only affects hint gathering, so the resident ASR model is never re-warmed and
    /// no loading pulse appears. The toggle is not menu-visible, so the status menu
    /// is not rebuilt.
    func applySpellCheckHints(_ enabled: Bool) {
        var config = ConfigStore.load(from: defaults)
        config.useSpellCheckHints = enabled
        do {
            try ConfigStore.save(config, to: defaults)
        } catch {
            logger.error("config save failed")
            return
        }
        let cleanupConfig = config.cleanupConfig
        Task { @MainActor in
            await composition?.orchestrator.updateCleanupConfig(cleanupConfig)
        }
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
