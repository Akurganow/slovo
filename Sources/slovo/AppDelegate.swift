import AppKit
import Settings
import SlovoCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let logger: Logger
    let defaults: UserDefaults
    /// Injected like `defaults`, with the live system reader as the default, so this
    /// layer names the capability instead of hard-wiring a preferences call. Read
    /// afresh on every menu open — the macOS setting changes while Slovo runs.
    let fnKeyAssignmentReader: FnKeyAssignmentReading
    /// Key presence is an APP fact, not a pipeline fact: the app owns the provider
    /// and injects it into the pipeline, so has-key / save-key / cleanup
    /// availability never depend on whether the pipeline composite exists yet.
    let openRouterKeyProvider = KeychainOpenRouterKeyProvider()
    /// The app's state and its one mutation path, seeded once in `init`. A stored
    /// `let`: a computed form would hand every reader a different store.
    let store: AppStore
    /// Owned here and injected into every composition, like the key provider: the
    /// pipeline is rebuilt on a permission grant, on Retry Setup and on the hotkey
    /// retry, and none of those may download or load the speech model again.
    private let speechModel: SharedSpeechModel
    var statusItem: NSStatusItem?
    var statusTextItem: NSMenuItem?
    var composition: AppComposition.Live?
    var settingsWindowController: SettingsWindowController?
    // Internal (not private) so the AppDelegate+About extension in its own file can
    // reach the cached window; a repeat click must focus it, not open a second one.
    var aboutWindow: AboutWindow?
    private var vocabularyQuickAddWindow: VocabularyQuickAddWindow?
    private var openRouterKeyWindow: OpenRouterKeyWindow?
    private var didShowPipelineStatus = false
    var isPipelineActive = false
    // A brief self-clearing failure glyph is on screen; settleToIdle must not stomp
    // it back to idle mid-window.
    var isShowingBriefStatus = false
    var isModelReady = false
    private var briefStatusResetTask: Task<Void, Never>?
    // Sibling of briefStatusResetTask: the pending reset of the user-action-failure
    // glyph flash, cancelled before a new flash so overlaps don't stack.
    var userActionFailureResetTask: Task<Void, Never>?
    private var hotkeyEdgeSequencer: HotkeyEdgeSequencer?
    private var isRebuildingPipeline = false
    // Strong reference is load-bearing: Sparkle holds the updater and user-driver
    // delegates weakly, so the coordinator would deallocate without this.
    var updaterCoordinator: UpdaterCoordinator?
    // The one persistent update-line item, built by DictationMenuBuilder and mutated
    // in place by the update renderer; never rebuilt on a transition.
    var updateMenuItem: NSMenuItem?
    // The one persistent fn-conflict row, built by DictationMenuBuilder only while fn
    // is bound in some role; the fn listener shows or hides it as the verdict in
    // state changes. Nil for every other trigger, which cannot collide.
    var fnConflictMenuItem: NSMenuItem?
    // The dictation menu's mute item, stored by DictationMenuBuilder on every
    // dictation build; renderMuteAvailability enables or disables it in place.
    var muteMenuItem: NSMenuItem?

    init(
        logger: Logger,
        defaults: UserDefaults = .standard,
        fnKeyAssignmentReader: FnKeyAssignmentReading = SystemFnKeyAssignmentReader()
    ) {
        self.logger = logger
        self.defaults = defaults
        self.fnKeyAssignmentReader = fnKeyAssignmentReader
        store = AppStore(state: AppState(
            config: ConfigStore.load(from: defaults),
            isOpenRouterKeyPresent: openRouterKeyProvider.hasConfiguredKey(),
            isFnKeySystemAssigned: fnKeyAssignmentReader.isFnKeySystemAssigned
        ))
        speechModel = SharedSpeechModel(config: store.state.config)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // AppKit resolves the stored position when the item adopts the autosave name,
        // so the seed must already be in place before the item is created and named.
        StatusItemPlacement.seedPreferredPositionIfAbsent(in: defaults)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = StatusItemPlacement.autosaveName
        paintIdleGlyph(on: item.button)
        statusItem = item
        startStoreEffects()
        startObservingOutputMuteAvailability()
        startPipeline()
        startUpdater()
        logger.info("menu bar app ready")
    }

    func makeMenu(
        _ input: DictationMenuInput,
        rows: DictationMenuRows,
        indication: UpdateIndication,
        muteAvailability: OutputMuteAvailability
    ) -> NSMenu {
        let built = DictationMenuBuilder(target: self).make(input, rows: rows)
        statusTextItem = built.statusItem
        renderUpdateIndication(indication)
        renderMuteAvailability(muteAvailability)
        return built.menu
    }

    private func startPipeline() {
        // The composition is seeded from the store, so a key added or removed
        // outside Slovo must reach it before it is built.
        store.update { $0.isOpenRouterKeyPresent = openRouterKeyProvider.hasConfiguredKey() }
        do {
            let live = try AppComposition.makeLive(
                state: store.state,
                openRouterKeyProvider: openRouterKeyProvider,
                speechModel: speechModel,
                statusReporter: { [weak self] status in
                    Task { @MainActor [weak self] in
                        self?.showStatus(status)
                    }
                },
                onCleanupFailure: scopeFailureObserver()
            )
            composition = live
            store.update { $0.vocabulary = listVocabulary() }
            guard live.onboardingSteps == [.ready] else {
                presentOnboarding(live.onboardingSteps)
                logger.info("onboarding pending")
                return
            }
            prepareModelGate(for: live)
            let sequencer = HotkeyEdgeSequencer { [weak self, orchestrator = live.orchestrator] edge in
                switch edge.phase {
                // A press stamped busy arrived while an earlier edge still held this
                // sink. Servicing it now would open the microphone after its own key
                // was released, and the repaint below would overwrite the live glyph.
                case .down(let mode): guard !edge.arrivedWhileBusy else { return await MainActor.run { self?.logRefusedPress() } }
                    guard await MainActor.run(body: { self?.isModelReady == true })
                    else { return await MainActor.run { self?.showModelLoadingState() } }
                    await MainActor.run {
                        self?.isPipelineActive = true
                        self?.didShowPipelineStatus = false
                        // The recording glyph is the semantic family, derived in
                        // applyRecordingGlyph from the live availability (letter
                        // mnemonics: MenuBarGlyph.forRecording).
                        self?.applyRecordingGlyph(mode)
                        self?.store.update { $0.statusLine = .recording }
                    }
                    await orchestrator.handle(.startRequested)
                case .translateLatched:
                    guard await MainActor.run(body: { self?.isPipelineActive == true }) else { return }
                    await MainActor.run { self?.applyRecordingGlyph(.translate) }
                case .up(let mode): guard await MainActor.run(body: { self?.isPipelineActive == true }) else { return }
                    await MainActor.run {
                        self?.setStatusGlyph(.processing, on: self?.statusItem?.button)
                        if self?.didShowPipelineStatus == false {
                            self?.store.update { $0.statusLine = .processing }
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
                store.update { $0.applyScope(.pipelineStarted) }
                logger.info("production composition started")
            } catch {
                presentHotkeyRecovery()
                logger.error("hotkey monitor failed")
            }
        } catch {
            logger.error("production composition failed")
        }
    }

    /// A refused press shows the user nothing, since it captured no speech. This line
    /// is the only way to tell it from a press the key tap never delivered. A method,
    /// not an inline call, because the sink closure sits at its length ceiling and the
    /// refusal may cost exactly one line there.
    private func logRefusedPress() {
        logger.info("press refused: earlier key edge still being handled")
    }

    /// Derives and paints the recording glyph for a session's mode from the LIVE
    /// cleanup availability. The availability is read exactly once — here, as the
    /// derivation argument — so no sequencer arm carries a separate gate read that a
    /// mutant could leave dead while still running the paint; both arms share this.
    func applyRecordingGlyph(_ mode: DictationMode) {
        let glyphMode = MenuBarGlyph.recordingGlyphMode(mode: mode, isCleanupOn: store.state.cleanupAvailability.isOn)
        setStatusGlyph(recording: glyphMode, on: statusItem?.button)
    }

    /// Return the menu-bar glyph and status line to idle — the hold-to-talk hint —
    /// when a session settles (normal stop or a silent cancel), leaving a
    /// sad-to-fail notice or an already-shown pipeline status untouched.
    private func settleToIdle() {
        isPipelineActive = false
        if !isShowingBriefStatus {
            paintIdleGlyph(on: statusItem?.button)
        }
        if !didShowPipelineStatus {
            store.update { $0.statusLine = .idle }
        }
    }

    private func presentOnboarding(_ steps: [OnboardingStep]) {
        // Setup surfaces through the menu-bar status and the onboarding menu only —
        // no modal alert. Permissions are requested from that menu, which triggers
        // the system prompts (menu-bar-only UX). The old per-permission "Continue
        // Setup" dialog re-appeared once for each permission because its dedup keyed
        // on the shrinking set of still-pending steps.
        // This composition is not gated (startPipeline returned above
        // prepareModelGate), so nothing else would ever stop a pulse inherited from
        // the composition it replaced.
        clearModelLoadingState()
        store.update { $0.menuMode = .onboarding(steps) }
    }

    func makeOnboardingMenu(for steps: [OnboardingStep]) -> NSMenu {
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
        store.update { $0.menuMode = .hotkeyRecovery }
    }

    func makeHotkeyRecoveryMenu() -> NSMenu {
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
        guard store.state.menuMode.isOnboarding else { return }
        refreshOnboardingMenuIfNeeded()
    }

    private func refreshOnboardingMenuIfNeeded() {
        let latestSteps = FirstRunFlow.pendingSteps(permissions: SystemPermissionPreflighter().preflight())
        guard store.state.menuMode != .onboarding(latestSteps) else { return }
        if latestSteps == [.ready] {
            retrySetup()
        } else {
            store.update { $0.menuMode = .onboarding(latestSteps) }
        }
    }

    func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func showStatus(_ status: StatusMessage) {
        guard status.isPersistentNotice
            || status.isSadToFailNotice
            || status.isNoSpeechNotice
            || isPipelineActive else {
            return
        }
        // The empty result flashes the red glyph ONLY: no status-line text and no
        // didShowPipelineStatus latch, so settleToIdle still returns the line to the
        // idle hint while the brief glyph rides out its window — the spec wants the
        // flash without a lingering notice ("do not distract the user").
        if status.isNoSpeechNotice {
            flashBriefStatusGlyph(status)
            return
        }
        if status.isPersistentNotice {
            didShowPipelineStatus = true
        }
        if status.isSadToFailNotice {
            didShowPipelineStatus = true
        }
        if status.isFailureNotice {
            flashBriefStatusGlyph(status)
        }
        store.update { $0.statusLine = .message(status) }
    }

    /// Flashes the unified red dictation-failure glyph and schedules its self-clear.
    /// Persistent failures retain their status text while the glyph itself resets.
    private func flashBriefStatusGlyph(_ status: StatusMessage) {
        isShowingBriefStatus = true
        setStatusGlyph(status: status, on: statusItem?.button)
        briefStatusResetTask?.cancel()
        briefStatusResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            // The order below IS the mechanism; each step is load-bearing.
            // 1. A cancelled sleep resumes by THROWING (SE-0304) and the `try?`
            //    above discards that, so the cancel alone stops nothing: without
            //    this the superseded reset runs on and clears the newer flash.
            guard !Task.isCancelled, let self else { return }
            // 2. Unconditionally, and before any other exit: this line is the ONLY
            //    writer that clears the latch, and settleToIdle, the model gate and
            //    the update menu all read it as a do-not-repaint-idle veto — a return
            //    above it strands the latch set and suppresses idle indefinitely.
            self.isShowingBriefStatus = false
            // 3. The PAINT alone is gated: a dictation that began inside the window
            //    owns the glyph, and idle here would blank its recording glyph until
            //    key-up. Its own settleToIdle repaints idle, the latch now cleared.
            guard !self.isPipelineActive else { return }
            self.paintIdleGlyph(on: self.statusItem?.button)
            if !status.isPersistentNotice {
                self.store.update { $0.statusLine = .idle }
            }
        }
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

    /// Opens the dedicated Add-OpenRouter-Key window — the no-key menu-bar affordance.
    /// Save routes through the existing key-save path (`saveOpenRouterKey` → provider
    /// store + the store's key-presence write), so every surface repaints as it does
    /// for a pane save; the window closes itself on save or cancel.
    @objc
    func showAddOpenRouterKeyWindow() {
        if openRouterKeyWindow == nil {
            openRouterKeyWindow = OpenRouterKeyWindow(onSave: { [weak self] key in
                self?.saveOpenRouterKey(key)
            })
        }
        openRouterKeyWindow?.show()
    }

    @objc
    private func retrySetup() {
        // A rebuild is asynchronous (it joins the previous edge consumer first); a
        // second retry arriving before it finishes must not spawn a parallel
        // teardown+rebuild that could leave a mismatched sequencer and composition.
        guard !isRebuildingPipeline else { return }
        isRebuildingPipeline = true
        composition?.hotkeyMonitor.stop()
        store.update {
            $0.menuMode = .dictation
            $0.statusLine = .idle
        }
        // Join the previous edge consumer before a new one is built, so a rebuilt
        // monitor cannot leave two consumers double-handling the same fn edges.
        let previousSequencer = hotkeyEdgeSequencer
        Task { @MainActor in
            await previousSequencer?.stop()
            // startPipeline() through isRebuildingPipeline = false must stay synchronous:
            // an await between them would hold the re-entrancy guard across a suspension,
            // and a Retry Setup arriving there — a permission granted just after this
            // composition read the preflight — would be dropped by the guard above with
            // nothing left to rebuild for it.
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

    @objc
    func toggleCleanupDictation(_ sender: NSMenuItem) {
        store.update { $0.config.cleanupEnabled.toggle() }
    }

    @objc
    func toggleMuteWhileDictating(_ sender: NSMenuItem) {
        store.update { $0.config.mutesSystemAudioWhileDictating.toggle() }
    }
}
