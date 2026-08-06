import AppKit
import SlovoCore

extension AppDelegate {
    func applyTrigger(_ trigger: HotkeyTrigger) {
        applyHotkeyChange { $0.trigger = trigger }
    }

    func applyTranslateTrigger(_ trigger: HotkeyTrigger) {
        applyHotkeyChange { $0.translateTrigger = trigger }
    }

    func applyTranslateKeyIsAdditional(_ isAdditional: Bool) {
        applyHotkeyChange { $0.translateKeyIsAdditional = isAdditional }
    }

    /// The one apply path behind every key setting: persist, hand the live tap the
    /// SAVED configuration, refresh the menu. It never rebuilds the pipeline — the
    /// resident ASR model is not re-warmed and the "Preparing Speech Model" pulse
    /// never appears (mirrors `applyCleanupModel`); the tap's event mask is
    /// key-independent, so `reconfigure` swaps the decision core in place. The menu is
    /// rebuilt because both header hints ("Hold <key> to talk", "Add <key> to
    /// translate") name the keys. A refused pair leaves everything untouched — the
    /// store is where mutual exclusion is decided.
    private func applyHotkeyChange(_ change: (inout Config) -> Void) {
        var config = ConfigStore.load(from: defaults)
        change(&config)
        do {
            try ConfigStore.save(config, to: defaults)
        } catch {
            logger.error("config save failed")
            return
        }
        composition?.hotkeyMonitor.reconfigure(configuration: config.hotkeyConfiguration)
        installStatusMenu()
    }
}
