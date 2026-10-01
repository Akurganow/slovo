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
    /// Builds the Settings window once (three panes) and shows it, activating the
    /// app first. Slovo is an `.accessory` app, so without `activate` the window
    /// opens behind other apps; the SwiftUI `openSettings` / `SettingsLink` route is
    /// deliberately avoided — it is broken for menu-bar apps on macOS 26.
    @objc
    func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = makeSettingsWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.show()
    }

    private func makeSettingsWindowController() -> SettingsWindowController {
        SettingsWindowController(panes: [
            Settings.Pane(
                identifier: Settings.PaneIdentifier("general"),
                title: "General",
                toolbarIcon: Self.toolbarIcon("gearshape")
            ) { GeneralSettingsPane(actions: self) },
            Settings.Pane(
                identifier: Settings.PaneIdentifier("cleanup"),
                title: "Cleanup",
                toolbarIcon: Self.toolbarIcon("wand.and.stars")
            ) { CleanupSettingsPane(actions: self) },
            Settings.Pane(
                identifier: Settings.PaneIdentifier("vocabulary"),
                title: "Vocabulary",
                toolbarIcon: Self.toolbarIcon("text.book.closed")
            ) { VocabularySettingsPane(actions: self) },
        ])
    }

    private static func toolbarIcon(_ symbol: String) -> NSImage {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 1, height: 1))
    }
}
