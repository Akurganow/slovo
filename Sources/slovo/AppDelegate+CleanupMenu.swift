import AppKit
import SlovoCore

extension AppDelegate {
    /// The Cleanup Model submenu over `options`, the state's catalog ∩ scope. No
    /// custom row in the menu, so a custom effective id carries no checkmark.
    func modelMenu(title: String, options: [CleanupModelOption], selectedModel: String) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        for option in options {
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
        store.update { $0.config.openRouterModel = option.id }
    }
}
