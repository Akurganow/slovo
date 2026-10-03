import AppKit
import LaunchAtLogin
import Settings
import SlovoCore

extension AppDelegate: SettingsActions {
    func launchAtLoginEnabled() -> Bool {
        // A system-service (SMAppService) read: no pipeline rebuild, no ASR re-warm.
        LaunchAtLogin.isEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        // Registers/unregisters the login item via SMAppService; a pure system-
        // service write like saveOpenRouterKey() — no pipeline rebuild, no ASR
        // re-warm.
        LaunchAtLogin.isEnabled = enabled
    }

    func saveOpenRouterKey(_ key: String) {
        // The cleaner reads the key lazily, so a save needs no rebuild and never
        // re-warms ASR. Key presence is read back on both outcomes: a failed save may
        // already have deleted the old item. The scope event follows a success only.
        var scopeEvent: CleanupScopeEvent?
        do {
            try openRouterKeyProvider.store(key)
            scopeEvent = .keySaved
        } catch {
            logger.error("openrouter key save failed")
            flashUserActionFailure()
        }
        writeKeyPresence(applying: scopeEvent)
    }

    func removeOpenRouterKey() {
        // The mirror of saveOpenRouterKey. A delete flips the effective state to
        // offNoKey; a failed one leaves the key stored. Either way key presence is
        // read back from the provider.
        var scopeEvent: CleanupScopeEvent?
        do {
            try openRouterKeyProvider.removeKey()
            scopeEvent = .keyRemoved
        } catch {
            logger.error("openrouter key removal failed")
            flashUserActionFailure()
        }
        writeKeyPresence(applying: scopeEvent)
    }

    func addVocabulary(_ commaSeparatedTerms: String) {
        let records = VocabularyQuickAdd.records(from: commaSeparatedTerms)
        guard !records.isEmpty else { return }
        do {
            // No rebuild: vocabulary is re-read from the database at the start of
            // every dictation, so new terms apply on the next one.
            try composition?.personalization.addVocabulary(records)
        } catch {
            logger.error("vocabulary add failed")
        }
        store.update { $0.vocabulary = listVocabulary() }
    }

    func removeVocabulary(id: Int64) {
        do {
            try composition?.personalization.removeVocabulary(id: id)
        } catch {
            logger.error("vocabulary remove failed")
        }
        store.update { $0.vocabulary = listVocabulary() }
    }

    /// Opens the third-party license notices bundled in the app's Resources
    /// (THIRD-PARTY-NOTICES.md, staged there by the packaging scripts) in the
    /// user's default handler.
    func openAcknowledgements() {
        guard let url = Bundle.main.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "md") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The vocabulary mirror's one read of the database, for the seed in
    /// `startPipeline` and both edits. Not part of `SettingsActions`.
    func listVocabulary() -> [VocabularyRecord] {
        do {
            return try composition?.personalization.allVocabulary() ?? []
        } catch {
            logger.error("vocabulary list failed")
            return []
        }
    }

    /// Ends a key save or removal: reads key presence back from the provider on both
    /// outcomes, and applies the scope event only when the provider call succeeded.
    private func writeKeyPresence(applying scopeEvent: CleanupScopeEvent?) {
        store.update {
            $0.isOpenRouterKeyPresent = openRouterKeyProvider.hasConfiguredKey()
            if let scopeEvent { $0.applyScope(scopeEvent) }
        }
    }
}

extension AppDelegate {
    /// The dropdown's Settings… item: the last settings pane viewed, never About.
    @objc
    func showSettingsWindow() {
        showSettings(on: store.state.lastSettingsPane)
    }

    /// The dropdown's About Slovo item.
    @objc
    func showAboutPane() {
        showSettings(on: .about)
    }

    /// Builds the Settings window once and shows it on `pane`, activating the app
    /// first. Slovo is an `.accessory` app, so without `activate` the window opens
    /// behind other apps; the SwiftUI `openSettings` / `SettingsLink` route is
    /// deliberately avoided — it is broken for menu-bar apps on macOS 26.
    private func showSettings(on pane: SettingsPaneID) {
        NSApp.activate(ignoringOtherApps: true)
        // The first open uses show(pane:): a toolbar action sent in the same pass as the first show() throws an AppKit
        // layer-backing exception. Later opens send the toolbar item's action instead. show(pane:) would switch without
        // the crossfade, re-insert a pane an earlier crossfade left at alpha 0, and skip the resize to that pane's height.
        guard let controller = settingsWindowController else {
            let controller = SettingsWindowController(panes: SettingsPaneID.allCases.map(settingsPane(for:)))
            settingsPaneObservation = controller.window?.toolbar?.observe(\.selectedItemIdentifier) { [weak self] toolbar, _ in
                // NSToolbar is main-actor isolated, and KVO calls back on the thread that makes the change.
                MainActor.assumeIsolated {
                    let shown = toolbar.selectedItemIdentifier
                        .flatMap { SettingsPaneID(rawValue: Settings.PaneIdentifier(fromToolbarItemIdentifier: $0).rawValue) }
                    self?.store.update { $0.recordSettingsPane(shown) }
                }
            }
            settingsWindowController = controller
            controller.show(pane: pane.paneIdentifier)
            return
        }
        if let item = controller.window?.toolbar?.items.first(where: { $0.itemIdentifier == pane.paneIdentifier.toolbarItemIdentifier }),
           let action = item.action {
            NSApp.sendAction(action, to: item.target, from: item)
        }
        controller.show()
    }

    private func settingsPane(for pane: SettingsPaneID) -> any SettingsPaneConvertible {
        switch pane {
        case .general:
            Settings.Pane(identifier: pane.paneIdentifier, title: "General", toolbarIcon: Self.toolbarIcon("gearshape")) {
                GeneralSettingsPane(actions: self)
            }
        case .cleanup:
            Settings.Pane(identifier: pane.paneIdentifier, title: "Cleanup", toolbarIcon: Self.toolbarIcon("wand.and.stars")) {
                CleanupSettingsPane(actions: self)
            }
        case .vocabulary:
            Settings.Pane(identifier: pane.paneIdentifier, title: "Vocabulary", toolbarIcon: Self.toolbarIcon("text.book.closed")) {
                VocabularySettingsPane(actions: self)
            }
        case .about:
            Settings.Pane(identifier: pane.paneIdentifier, title: "About", toolbarIcon: Self.toolbarIcon("info.circle")) {
                AboutSettingsPane(actions: self)
            }
        }
    }

    private static func toolbarIcon(_ symbol: String) -> NSImage {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 1, height: 1))
    }
}

private extension SettingsPaneID {
    /// The package's identifier for this pane. The selection handler maps a toolbar
    /// item back to it.
    var paneIdentifier: Settings.PaneIdentifier { Settings.PaneIdentifier(rawValue) }
}
