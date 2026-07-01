import AppKit
import SlovoCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let setupAlertStepsKey = "setup.alert.steps"

    private let logger: Logger
    let defaults: UserDefaults
    private var statusItem: NSStatusItem?
    private var statusTextItem: NSMenuItem?
    private var composition: AppComposition.Live?
    private var didShowPipelineStatus = false
    private var isPipelineActive = false
    private var isShowingSadToFailStatus = false
    private var onboardingSteps: [OnboardingStep] = []
    private var sadToFailResetTask: Task<Void, Never>?

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
        let menu = NSMenu()
        let title = NSMenuItem(title: "Slovo", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        let status = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusTextItem = status
        menu.addItem(.separator())
        let config = ConfigStore.load(from: defaults)
        menu.addItem(modelMenu(
            title: "Cleanup Model: \(CleanupModelCatalog.displayName(for: config.openRouterModel))",
            selectedModel: config.openRouterModel
        ))
        menu.addItem(.separator())
        menu.addItem(actionItem("Update OpenRouter Key", #selector(enterOpenRouterKey)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Slovo",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        return menu
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
            defaults.removeObject(forKey: Self.setupAlertStepsKey)
            try? live.openRouterKeyProvider.preload()
            live.hotkeyMonitor.onTrigger = { [weak self, orchestrator = live.orchestrator] phase in
                Task {
                    switch phase {
                    case .down:
                        await MainActor.run {
                            self?.isPipelineActive = true
                            self?.didShowPipelineStatus = false
                            self?.setStatusGlyph(.recording, on: self?.statusItem?.button)
                            self?.statusTextItem?.title = "Status: Recording"
                        }
                        await orchestrator.handle(.startRequested)
                    case .up:
                        await MainActor.run {
                            self?.setStatusGlyph(.processing, on: self?.statusItem?.button)
                            if self?.didShowPipelineStatus == false {
                                self?.statusTextItem?.title = "Status: Processing"
                            }
                        }
                        await orchestrator.handle(.stopRequested)
                        await orchestrator.awaitPipelineDrain()
                        await MainActor.run {
                            self?.isPipelineActive = false
                            if self?.isShowingSadToFailStatus == false {
                                self?.setStatusGlyph(.idle, on: self?.statusItem?.button)
                            }
                            if self?.didShowPipelineStatus == false {
                                self?.statusTextItem?.title = "Status: Idle"
                            }
                        }
                    }
                }
            }
            try live.hotkeyMonitor.start()
            logger.info("production composition started")
        } catch {
            logger.error("production composition failed")
        }
    }

    private func setStatusGlyph(_ state: DictationState, on button: NSStatusBarButton?) {
        guard let button else { return }
        button.title = ""
        button.contentTintColor = nil
        button.image = Self.menuBarGlyphImage(MenuBarGlyph.forState(state))
            ?? NSImage(systemSymbolName: "mic", accessibilityDescription: "Slovo")
    }

    private func setStatusGlyph(status: StatusMessage, on button: NSStatusBarButton?) {
        guard let button, let glyph = MenuBarGlyph.forStatus(status) else { return }
        button.title = ""
        button.contentTintColor = MenuBarGlyph.tint(forStatus: status) == .error ? .systemRed : nil
        button.image = Self.menuBarGlyphImage(glyph)
            ?? NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "Slovo")
    }

    private func presentOnboarding(_ steps: [OnboardingStep]) {
        onboardingSteps = steps
        statusTextItem?.title = "Status: Setup Required"
        statusItem?.menu = makeOnboardingMenu(for: steps)
        showOnboardingAlertIfNeeded(for: steps)
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
        if steps.contains(.requestInputMonitoring) {
            menu.addItem(actionItem("Request Input Monitoring Access", #selector(openInputMonitoringSettings)))
        }
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

    private func showOnboardingAlert(for steps: [OnboardingStep]) {
        let alert = NSAlert()
        alert.messageText = "Slovo needs setup before dictation starts."
        alert.informativeText = steps.map(Self.title(for:)).joined(separator: "\n")
        alert.addButton(withTitle: primaryActionTitle(for: steps))
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { @MainActor in
            await requestPrimaryOnboardingStep(steps)
        }
    }

    private func showOnboardingAlertIfNeeded(for steps: [OnboardingStep]) {
        let signature = steps.map(Self.title(for:)).joined(separator: "|")
        guard defaults.string(forKey: Self.setupAlertStepsKey) != signature else { return }
        defaults.set(signature, forKey: Self.setupAlertStepsKey)
        showOnboardingAlert(for: steps)
    }

    private func requestPrimaryOnboardingStep(_ steps: [OnboardingStep]) async {
        if steps.contains(.requestMicrophone) {
            await requestPermission(.microphone, fallbackPane: "Privacy_Microphone")
        } else if steps.contains(.requestAccessibility) {
            await requestPermission(.accessibility, fallbackPane: "Privacy_Accessibility")
        } else if steps.contains(.requestInputMonitoring) {
            await requestPermission(.inputMonitoring, fallbackPane: "Privacy_ListenEvent")
        }
    }

    private func primaryActionTitle(for steps: [OnboardingStep]) -> String {
        "Continue Setup"
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
    private func enterOpenRouterKey() {
        promptForOpenRouterKey()
    }

    @objc
    private func retrySetup() {
        composition?.hotkeyMonitor.stop()
        statusItem?.menu = makeMenu()
        startPipeline()
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

    private func promptForOpenRouterKey() {
        promptForAPIKey(
            title: "Enter OpenRouter API key",
            save: { [weak self] key in
                guard let provider = self?.composition?.openRouterKeyProvider else { return }
                try provider.store(key)
            }
        )
    }

    private func promptForAPIKey(
        title: String,
        save: (String) throws -> Void
    ) {
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "The key is stored in Keychain."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try save(field.stringValue)
            retrySetup()
        } catch {
            logger.error("openrouter key save failed")
        }
    }

    func updateConfig(_ mutate: (inout Config) -> Void) {
        var config = ConfigStore.load(from: defaults)
        mutate(&config)
        do {
            try ConfigStore.save(config, to: defaults)
            retrySetup()
        } catch {
            logger.error("config save failed")
        }
    }

    private static func title(for step: OnboardingStep) -> String {
        switch step {
        case .requestMicrophone:
            return "Microphone permission"
        case .requestAccessibility:
            return "Accessibility permission"
        case .requestInputMonitoring:
            return "Input Monitoring permission"
        case .ready:
            return "Ready"
        }
    }
}
