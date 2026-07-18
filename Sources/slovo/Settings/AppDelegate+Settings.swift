import AppKit
import LaunchAtLogin
import Settings
import SlovoCore
import SwiftUI

extension AppDelegate: SettingsActions {
    func currentConfig() -> Config {
        ConfigStore.load(from: defaults)
    }

    func hasOpenRouterKey() -> Bool {
        composition?.openRouterKeyProvider.hasConfiguredKey() ?? false
    }

    func launchAtLoginEnabled() -> Bool {
        // A system-service (SMAppService) read, like hasOpenRouterKey()'s Keychain
        // read: no pipeline rebuild, no ASR re-warm.
        LaunchAtLogin.isEnabled
    }

    func setTrigger(_ trigger: HotkeyTrigger) {
        // Live monitor reconfigure, no pipeline rebuild (Plan 1's apply path).
        applyTrigger(trigger)
    }

    func setRecognitionLanguage(_ language: Language) {
        var config = ConfigStore.load(from: defaults)
        config.language = language
        guard persist(config) else { return }
        // The ASR engine binds its language at construction, so a recognition-language
        // change is the one Settings change that re-warms the model — an honest ASR
        // change, unlike the cleanup-model swap which must never rebuild.
        retrySetup()
    }

    func setTranslationLanguage(_ language: Language) {
        // Live: persist + push to the running orchestrator, no rebuild — the target
        // only shapes the translate-mode prompt, so the resident ASR model is never
        // re-warmed (unlike the recognition-language change).
        applyTranslationLanguage(language)
    }

    func setCleanupModel(_ modelId: String) {
        // Live: persist + push to the running orchestrator, no rebuild (#2).
        applyCleanupModel(modelId)
    }

    func setWritingStyle(_ style: WritingStyle) {
        var config = ConfigStore.load(from: defaults)
        config.writingStyle = style
        guard persist(config) else { return }
        let cleanupConfig = config.cleanupConfig
        Task { @MainActor in
            await composition?.orchestrator.updateCleanupConfig(cleanupConfig)
        }
    }

    func setSpellCheckHints(_ enabled: Bool) {
        // Live: persist + push to the running orchestrator, no rebuild — hint
        // gathering only, so the resident ASR model is never re-warmed.
        applySpellCheckHints(enabled)
    }

    func setAutomaticallyInstallsUpdates(_ enabled: Bool) {
        var config = ConfigStore.load(from: defaults)
        config.automaticallyInstallsUpdates = enabled
        guard persist(config) else { return }
        // Apply live to the running updater so OFF halts the scheduler at once (no
        // feed fetch, no download); no pipeline rebuild, no ASR re-warm.
        if let updater = updaterCoordinator?.updater {
            UpdaterActivation.apply(automaticUpdatesEnabled: enabled, to: updater)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        // Registers/unregisters the login item via SMAppService; a pure system-
        // service write like saveOpenRouterKey() — no pipeline rebuild, no ASR
        // re-warm.
        LaunchAtLogin.isEnabled = enabled
    }

    func saveOpenRouterKey(_ key: String) {
        // The cleaner reads the key lazily at cleanup time, so a save needs no
        // rebuild and never re-warms ASR.
        do {
            try composition?.openRouterKeyProvider.store(key)
        } catch {
            logger.error("openrouter key save failed")
        }
    }

    func listVocabulary() -> [VocabularyRecord] {
        do {
            return try composition?.personalization.allVocabulary() ?? []
        } catch {
            logger.error("vocabulary list failed")
            return []
        }
    }

    func addVocabulary(_ commaSeparatedTerms: String) {
        let records = VocabularyQuickAdd.records(from: commaSeparatedTerms)
        guard !records.isEmpty else { return }
        do {
            // No rebuild: vocabulary is re-read from the store at the start of every
            // dictation, so new terms apply on the next one.
            try composition?.personalization.addVocabulary(records)
        } catch {
            logger.error("vocabulary add failed")
        }
    }

    func removeVocabulary(id: Int64) {
        do {
            try composition?.personalization.removeVocabulary(id: id)
        } catch {
            logger.error("vocabulary remove failed")
        }
    }

    /// Persists a translate-target change and applies it to the NEXT dictation live.
    /// Like `applyCleanupModel`, this does NOT rebuild the pipeline: the target only
    /// affects the cleanup prompt in translate mode, so the resident ASR model is
    /// never re-warmed and no loading pulse appears. The menu is refreshed so the
    /// selected-language checkmark and the "Translate to" title track the new choice.
    func applyTranslationLanguage(_ language: Language) {
        var config = ConfigStore.load(from: defaults)
        config.translationTargetLanguage = language
        guard persist(config) else { return }
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
        guard persist(config) else { return }
        let cleanupConfig = config.cleanupConfig
        Task { @MainActor in
            await composition?.orchestrator.updateCleanupConfig(cleanupConfig)
        }
    }

    /// Saves `config`, logging and abandoning the change on a validation/save error
    /// (no modal — the pane keeps its current value). Returns whether it persisted.
    private func persist(_ config: Config) -> Bool {
        do {
            try ConfigStore.save(config, to: defaults)
            return true
        } catch {
            logger.error("config save failed")
            return false
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
