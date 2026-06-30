import AppKit
import LoquiCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger: Logger
    private var statusItem: NSStatusItem?
    private var statusTextItem: NSMenuItem?
    private var composition: AppComposition.Live?
    private var didShowPipelineStatus = false

    init(logger: Logger) {
        self.logger = logger
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
        menu.addItem(NSMenuItem(
            title: "Quit Loqui",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        return menu
    }

    private func startPipeline() {
        do {
            let live = try AppComposition.makeLive(statusReporter: { [weak self] status in
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
            live.hotkeyMonitor.onTrigger = { [weak self, orchestrator = live.orchestrator] phase in
                Task {
                    switch phase {
                    case .down:
                        await MainActor.run {
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
            menu.addItem(actionItem("Open Microphone Settings", #selector(openMicrophoneSettings)))
        }
        if steps.contains(.requestAccessibility) {
            menu.addItem(actionItem("Open Accessibility Settings", #selector(openAccessibilitySettings)))
        }
        if steps.contains(.requestInputMonitoring) {
            menu.addItem(actionItem("Open Input Monitoring Settings", #selector(openInputMonitoringSettings)))
        }
        if steps.contains(.requestAnthropicKey) {
            menu.addItem(actionItem("Enter Anthropic Key", #selector(enterAnthropicKey)))
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
        openPrimaryOnboardingStep(steps)
    }

    private func openPrimaryOnboardingStep(_ steps: [OnboardingStep]) {
        if steps.contains(.requestMicrophone) {
            openSettingsPane("Privacy_Microphone")
        } else if steps.contains(.requestAccessibility) {
            openSettingsPane("Privacy_Accessibility")
        } else if steps.contains(.requestInputMonitoring) {
            openSettingsPane("Privacy_ListenEvent")
        } else if steps.contains(.requestAnthropicKey) {
            promptForAnthropicKey()
        }
    }

    private func primaryActionTitle(for steps: [OnboardingStep]) -> String {
        steps.contains(.requestAnthropicKey) && steps.count == 1 ? "Enter Key" : "Open Settings"
    }

    private func showStatus(_ status: StatusMessage) {
        didShowPipelineStatus = true
        statusTextItem?.title = "Status: \(Self.title(for: status))"
    }

    @objc
    private func openMicrophoneSettings() {
        openSettingsPane("Privacy_Microphone")
    }

    @objc
    private func openAccessibilitySettings() {
        openSettingsPane("Privacy_Accessibility")
    }

    @objc
    private func openInputMonitoringSettings() {
        openSettingsPane("Privacy_ListenEvent")
    }

    @objc
    private func enterAnthropicKey() {
        promptForAnthropicKey()
    }

    @objc
    private func retrySetup() {
        statusItem?.menu = makeMenu()
        startPipeline()
    }

    private func openSettingsPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func promptForAnthropicKey() {
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        let alert = NSAlert()
        alert.messageText = "Enter Anthropic API key"
        alert.informativeText = "The key is stored in Keychain."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try composition?.keyProvider.store(field.stringValue)
            retrySetup()
        } catch {
            logger.error("anthropic key save failed")
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
        case .ready:
            return "Ready"
        }
    }

    private static func title(for status: StatusMessage) -> String {
        switch status {
        case .cleanupDeclinedInsertedAsSpoken:
            return "Inserted As Spoken"
        case .accessibilityDenied:
            return "Accessibility Denied"
        case .missingKey:
            return "Missing Anthropic Key"
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

    private static func menuBarGlyphImage(_ glyph: Character) -> NSImage? {
        guard let font = NSFont(name: "NotoSansGlagolitic-Regular", size: 16) else {
            return nil
        }
        let text = NSAttributedString(
            string: String(glyph),
            attributes: [
                .font: font,
                .foregroundColor: NSColor.black,
            ]
        )
        let textSize = text.size()
        let image = NSImage(size: NSSize(width: ceil(textSize.width), height: ceil(textSize.height)))
        image.lockFocus()
        text.draw(at: .zero)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
