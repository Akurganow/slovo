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

    func make(
        trigger: HotkeyTrigger,
        selectedModelId: String,
        mutesSystemAudioWhileDictating: Bool,
        translationLanguage: String,
        cleanupAvailability: CleanupAvailability
    ) -> Built {
        let menu = NSMenu()
        // Explicit enable/disable control: auto-enablement would re-enable the
        // translate submenu and the no-key toggle that this builder disables.
        menu.autoenablesItems = false
        // The status dropdown is its own menu delegate: the hybrid update row needs
        // the willHighlight swap and the menuWillOpen re-sync.
        menu.delegate = target
        var statusItem = NSMenuItem()
        // Five config arguments no longer fit the strict 160-char line, so the call
        // is multiline per multiline_arguments_brackets; the source guards assert the
        // call token and the threaded trigger separately.
        for item in DictationMenu.items(
            trigger: trigger,
            selectedModelId: selectedModelId,
            mutesSystemAudioWhileDictating: mutesSystemAudioWhileDictating,
            translationLanguage: translationLanguage,
            cleanupAvailability: cleanupAvailability,
            update: .hidden
        ) {
            switch item {
            case .status(let word):
                let entry = disabled(word)
                statusItem = entry
                menu.addItem(entry)
            case .hotkeyHint(let text):
                menu.addItem(disabled(text))
                menu.addItem(makeUpdateItem())
            // This static build renders only the textual form of the update line;
            // the live hybrid "Update ready"/"Restart" behavior and in-place
            // mutation are owned by the app-target renderer, per the auto-update
            // design.
            case .updateDownloading(let version):
                menu.addItem(disabled("Downloading v\(version)"))
            case .updateReady(let version):
                menu.addItem(disabled("Update ready — v\(version)"))
            case .separator:
                menu.addItem(.separator())
            case .cleanupModel(let modelId, let enabled):
                let entry = target.modelMenu(
                    title: "Cleanup Model: \(CleanupModelCatalog.displayName(for: modelId))",
                    selectedModel: modelId
                )
                // Grayed but visible when cleanup is off with a key present: there is
                // a selection, it just cannot take effect — mirrors translationLanguage.
                entry.isEnabled = enabled
                menu.addItem(entry)
            case .addOpenRouterKey:
                // Replaces the whole cleanup block in the no-key state; opens Settings
                // → Cleanup so the user can add a key (the way out of no-key).
                menu.addItem(target.actionItem("Add OpenRouter Key…", #selector(AppDelegate.showCleanupSettingsForKey)))
            case .translationLanguage(let selected, let enabled):
                let entry = target.translationLanguageMenu(selected: selected)
                entry.isEnabled = enabled
                menu.addItem(entry)
            case .cleanupToggle(let isOn):
                // Always actionable: the switch is emitted only when a key is present,
                // so there is no off-and-disabled path to render — `isOn` only drives
                // the checkmark.
                let entry = target.actionItem(
                    "Clean Up Dictation",
                    #selector(AppDelegate.toggleCleanupDictation(_:))
                )
                entry.state = isOn ? .on : .off
                menu.addItem(entry)
            case .addVocabulary:
                menu.addItem(target.actionItem("Add Vocabulary…", #selector(AppDelegate.showVocabularyQuickAdd)))
            case .muteWhileDictating(let isOn):
                let entry = target.actionItem(
                    "Mute Audio While Dictating",
                    #selector(AppDelegate.toggleMuteWhileDictating(_:))
                )
                entry.state = isOn ? .on : .off
                menu.addItem(entry)
            case .about:
                menu.addItem(target.actionItem("About Slovo", #selector(AppDelegate.showAboutWindow)))
            case .settings:
                let entry = target.actionItem("Settings…", #selector(AppDelegate.showSettingsWindow))
                entry.keyEquivalent = ","
                // HIG-canonical settings symbol; SF Symbols render as template images,
                // so it adapts to the light/dark menu bar automatically.
                entry.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
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

    /// The one persistent update-line item, handed to the target so the update
    /// renderer mutates it in place. Hidden until the coordinator reports activity;
    /// the model's update cases stay unreached because this renderer-owned item is
    /// the runtime path.
    private func makeUpdateItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.isHidden = true
        target.updateMenuItem = item
        return item
    }
}
