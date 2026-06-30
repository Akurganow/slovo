import AppKit
import LoquiCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger: Logger
    private let defaults: UserDefaults
    private var statusItem: NSStatusItem?
    private var statusTextItem: NSMenuItem?
    private var composition: AppComposition.Live?
    private var didShowPipelineStatus = false
    private var isPipelineActive = false

    private enum APIKeyKind { case anthropic, openAI }

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
        let title = NSMenuItem(title: "Loqui", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        let status = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusTextItem = status
        menu.addItem(.separator())
        menu.addItem(actionItem("Use Anthropic Cleanup", #selector(useAnthropicCleanup)))
        menu.addItem(actionItem("Use OpenAI Cleanup", #selector(useOpenAICleanup)))
        menu.addItem(actionItem("Set Anthropic Model", #selector(setAnthropicModel)))
        menu.addItem(actionItem("Set OpenAI Model", #selector(setOpenAIModel)))
        menu.addItem(.separator())
        menu.addItem(actionItem("Update Anthropic Key", #selector(enterAnthropicKey)))
        menu.addItem(actionItem("Update OpenAI Key", #selector(enterOpenAIKey)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Loqui",
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
            try live.selectedKeyProvider.preload()
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
                            self?.setStatusGlyph(.idle, on: self?.statusItem?.button)
                            self?.isPipelineActive = false
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
        button.image = Self.menuBarGlyphImage(MenuBarGlyph.forState(state))
            ?? NSImage(systemSymbolName: "mic", accessibilityDescription: "Loqui")
    }

    private func presentOnboarding(_ steps: [OnboardingStep]) {
        statusTextItem?.title = "Status: Setup Required"
        statusItem?.menu = makeOnboardingMenu(for: steps)
        showOnboardingAlert(for: steps)
    }

    private func makeOnboardingMenu(for steps: [OnboardingStep]) -> NSMenu {
        let menu = NSMenu()
        let title = NSMenuItem(title: "Loqui Setup Required", action: nil, keyEquivalent: "")
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
        if steps.contains(.requestAnthropicKey) {
            menu.addItem(actionItem("Enter Anthropic Key", #selector(enterAnthropicKey)))
        }
        if steps.contains(.requestOpenAIKey) {
            menu.addItem(actionItem("Enter OpenAI Key", #selector(enterOpenAIKey)))
        }
        menu.addItem(.separator())
        menu.addItem(actionItem("Retry Setup", #selector(retrySetup)))
        menu.addItem(NSMenuItem(title: "Quit Loqui", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func showOnboardingAlert(for steps: [OnboardingStep]) {
        let alert = NSAlert()
        alert.messageText = "Loqui needs setup before dictation starts."
        alert.informativeText = steps.map(Self.title(for:)).joined(separator: "\n")
        alert.addButton(withTitle: primaryActionTitle(for: steps))
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { @MainActor in
            await requestPrimaryOnboardingStep(steps)
        }
    }

    private func requestPrimaryOnboardingStep(_ steps: [OnboardingStep]) async {
        if steps.contains(.requestMicrophone) {
            await requestPermission(.microphone, fallbackPane: "Privacy_Microphone")
        } else if steps.contains(.requestAccessibility) {
            await requestPermission(.accessibility, fallbackPane: "Privacy_Accessibility")
        } else if steps.contains(.requestInputMonitoring) {
            await requestPermission(.inputMonitoring, fallbackPane: "Privacy_ListenEvent")
        } else if steps.contains(.requestAnthropicKey) {
            promptForAnthropicKey()
        } else if steps.contains(.requestOpenAIKey) {
            promptForOpenAIKey()
        }
    }

    private func primaryActionTitle(for steps: [OnboardingStep]) -> String {
        (steps.contains(.requestAnthropicKey) || steps.contains(.requestOpenAIKey)) && steps.count == 1
            ? "Enter Key"
            : "Continue Setup"
    }

    private func showStatus(_ status: StatusMessage) {
        guard status.isPersistentNotice || isPipelineActive else { return }
        if status.isPersistentNotice {
            didShowPipelineStatus = true
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
    private func enterAnthropicKey() {
        promptForAnthropicKey()
    }

    @objc
    private func enterOpenAIKey() {
        promptForOpenAIKey()
    }

    @objc
    private func useAnthropicCleanup() {
        updateConfig { config in
            config.cleanupProvider = .anthropic
        }
    }

    @objc
    private func useOpenAICleanup() {
        updateConfig { config in
            config.cleanupProvider = .openAI
        }
    }

    @objc
    private func setAnthropicModel() {
        let current = ConfigStore.load(from: defaults).anthropicModel
        promptForModel(title: "Set Anthropic model", currentValue: current) { [weak self] model in
            self?.updateConfig { config in
                config.anthropicModel = model
            }
        }
    }

    @objc
    private func setOpenAIModel() {
        let current = ConfigStore.load(from: defaults).openAIModel
        promptForModel(title: "Set OpenAI model", currentValue: current) { [weak self] model in
            self?.updateConfig { config in
                config.openAIModel = model
            }
        }
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

    private func promptForAnthropicKey() {
        promptForAPIKey(
            title: "Enter Anthropic API key",
            save: { [weak self] key in
                guard let provider = self?.composition?.anthropicKeyProvider else { return }
                try provider.store(key)
            },
            kind: .anthropic
        )
    }

    private func promptForOpenAIKey() {
        promptForAPIKey(
            title: "Enter OpenAI API key",
            save: { [weak self] key in
                guard let provider = self?.composition?.openAIKeyProvider else { return }
                try provider.store(key)
            },
            kind: .openAI
        )
    }

    private func promptForAPIKey(
        title: String,
        save: (String) throws -> Void,
        kind: APIKeyKind
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
            switch kind {
            case .anthropic:
                logger.error("anthropic key save failed")
            case .openAI:
                logger.error("openai key save failed")
            }
        }
    }

    private func promptForModel(title: String, currentValue: String, save: (String) -> Void) {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.stringValue = currentValue
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Enter the provider model id."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let model = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        save(model)
    }

    private func updateConfig(_ mutate: (inout Config) -> Void) {
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
        case .requestAnthropicKey:
            return "Anthropic key"
        case .requestOpenAIKey:
            return "OpenAI key"
        case .ready:
            return "Ready"
        }
    }

    private static func title(for status: StatusMessage) -> String {
        switch status {
        case .preparingSpeechModel:
            return "Preparing Speech Model"
        case .cleanupDeclinedInsertedAsSpoken:
            return "Inserted As Spoken"
        case .accessibilityDenied:
            return "Accessibility Denied"
        case .missingKey:
            return "Missing Cleanup Key"
        case .transcriptionFailed:
            return "Transcription Failed"
        case .secureFieldActive:
            return "Secure Field Active"
        case .injectionFailed:
            return "Insertion Failed"
        case .microphoneUnavailable:
            return "Microphone Unavailable"
        case .cleanupFailed:
            return "Cleanup Failed"
        }
    }
}
