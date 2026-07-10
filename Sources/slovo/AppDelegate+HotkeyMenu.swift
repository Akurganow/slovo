import AppKit
import SlovoCore

extension AppDelegate {
    // TEMPORARY (Phase 1): a status-bar submenu to set the push-to-talk key.
    // Phase 2 moves this into the Settings window and removes the submenu.
    func triggerMenu(title: String, selectedTrigger: HotkeyTrigger) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        for trigger in HotkeyTrigger.allCases {
            let item = NSMenuItem(title: trigger.displayName, action: #selector(selectTrigger(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = trigger.rawValue
            item.state = trigger == selectedTrigger ? .on : .off
            menu.addItem(item)
        }
        parent.submenu = menu
        return parent
    }

    @objc
    func selectTrigger(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let trigger = HotkeyTrigger(rawValue: rawValue) else { return }
        applyTrigger(trigger)
    }

    /// Persists a push-to-talk key change and applies it to the live tap WITHOUT
    /// rebuilding the pipeline: the resident ASR model is never re-warmed and the
    /// "Preparing Speech Model" pulse never appears (mirrors `applyCleanupModel`).
    /// The tap's event mask is trigger-independent, so `reconfigure` swaps the
    /// decision core in place. The menu is refreshed so the checkmark and the
    /// "Hold <key> to talk" hint track the new choice.
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
        statusItem?.menu = makeMenu()
    }
}
