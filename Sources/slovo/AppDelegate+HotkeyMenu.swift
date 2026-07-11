import AppKit
import SlovoCore

extension AppDelegate {
    /// Persists a push-to-talk key change and applies it to the live tap WITHOUT
    /// rebuilding the pipeline: the resident ASR model is never re-warmed and the
    /// "Preparing Speech Model" pulse never appears (mirrors `applyCleanupModel`).
    /// The tap's event mask is trigger-independent, so `reconfigure` swaps the
    /// decision core in place. The menu is refreshed so the "Hold <key> to talk"
    /// hint tracks the new choice.
    func applyTrigger(_ trigger: HotkeyTrigger) {
        var config = ConfigStore.load(from: defaults)
        config.trigger = trigger
        do {
            try ConfigStore.save(config, to: defaults)
        } catch {
            logger.error("config save failed")
            return
        }
        composition?.hotkeyMonitor.reconfigure(trigger: trigger)
        installStatusMenu()
    }
}
