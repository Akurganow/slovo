import AppKit
import SlovoCore

extension AppDelegate {
    func modelMenu(title: String, selectedModel: String) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        for option in CleanupModelCatalog.options {
            let item = NSMenuItem(title: option.displayName, action: #selector(selectCleanupModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option
            item.state = option.id == selectedModel ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(actionItem("Custom Model...", #selector(promptForCustomCleanupModel)))
        parent.submenu = menu
        return parent
    }

    @objc
    func selectCleanupModel(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? CleanupModelOption else { return }
        updateConfig { config in
            config.openRouterModel = option.id
        }
    }

    @objc
    func promptForCustomCleanupModel() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = Config.defaultOpenRouterModel
        let alert = NSAlert()
        alert.messageText = "Enter OpenRouter model id"
        alert.informativeText = "The model id is saved in Slovo preferences."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let model = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        updateConfig { config in
            config.openRouterModel = model
        }
    }
}
