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
        parent.submenu = menu
        return parent
    }

    @objc
    func selectCleanupModel(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? CleanupModelOption else { return }
        applyCleanupModel(option.id)
    }
}
