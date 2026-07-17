import AppKit
import SlovoCore

extension AppDelegate {
    /// Builds the "Translate to" submenu from the recognition-language catalog,
    /// checkmarking the persisted target. No Auto row: a translate target must be a
    /// concrete language (the fail-closed config guard rejects the sentinel). Mirrors
    /// `modelMenu(title:selectedModel:)`.
    func translationLanguageMenu(selected: String) -> NSMenuItem {
        let title = "Translate to: \(RecognitionLanguageCatalog.displayName(for: selected) ?? selected)"
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        for option in RecognitionLanguageCatalog.options {
            let item = NSMenuItem(title: option.displayName, action: #selector(selectTranslationLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option
            item.state = option.code == selected ? .on : .off
            menu.addItem(item)
        }
        parent.submenu = menu
        return parent
    }

    @objc
    func selectTranslationLanguage(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? RecognitionLanguageOption else { return }
        applyTranslationLanguage(Language(rawValue: option.code))
    }
}
