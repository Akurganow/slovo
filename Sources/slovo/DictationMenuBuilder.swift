import AppKit
import SlovoCore

/// Renders the pure `DictationMenu` model into an `NSMenu`. Menu construction lives
/// here rather than in `AppDelegate` so the dropdown is assembled in one place and
/// its order/hint are driven by the unit-tested model.
@MainActor
struct DictationMenuBuilder {
    /// The delegate that owns the menu's selectors and the reused model submenu.
    unowned let target: AppDelegate

    /// The built menu plus the live status item the delegate keeps updating.
    struct Built {
        let menu: NSMenu
        let statusItem: NSMenuItem
    }

    func make(trigger: HotkeyTrigger, selectedModelId: String) -> Built {
        let menu = NSMenu()
        var statusItem = NSMenuItem()
        for item in DictationMenu.items(trigger: trigger, selectedModelId: selectedModelId) {
            switch item {
            case .title(let text):
                menu.addItem(disabled(text))
            case .status(let word):
                let entry = disabled("Status: \(word)")
                statusItem = entry
                menu.addItem(entry)
            case .hotkeyHint(let text):
                menu.addItem(disabled(text))
            case .separator:
                menu.addItem(.separator())
            case .cleanupModel(let modelId):
                menu.addItem(target.modelMenu(
                    title: "Cleanup Model: \(CleanupModelCatalog.displayName(for: modelId))",
                    selectedModel: modelId
                ))
            case .addVocabulary:
                menu.addItem(target.actionItem("Add Vocabulary...", #selector(AppDelegate.showVocabularyQuickAdd)))
            case .settings:
                let entry = target.actionItem("Settings...", #selector(AppDelegate.showSettingsWindow))
                entry.keyEquivalent = ","
                menu.addItem(entry)
            case .quit:
                menu.addItem(NSMenuItem(
                    title: "Quit Slovo",
                    action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: "q"
                ))
            }
        }
        return Built(menu: menu, statusItem: statusItem)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
