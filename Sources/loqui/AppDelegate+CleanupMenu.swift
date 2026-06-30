import AppKit
import LoquiCore

extension AppDelegate {
    func cleanupProviderMenu(config: Config) -> NSMenuItem {
        let parent = NSMenuItem(title: "Cleanup Provider", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Cleanup Provider")
        for provider in [CleanupProvider.anthropic, .openAI] {
            let item = NSMenuItem(title: title(for: provider), action: #selector(selectCleanupProvider(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = provider
            item.state = provider == config.cleanupProvider ? .on : .off
            menu.addItem(item)
        }
        parent.submenu = menu
        return parent
    }

    func modelMenu(title: String, provider: CleanupProvider, selectedModel: String) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        for option in CleanupModelCatalog.options(for: provider) {
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
    func selectCleanupProvider(_ sender: NSMenuItem) {
        guard let provider = sender.representedObject as? CleanupProvider else { return }
        updateConfig { config in
            config.cleanupProvider = provider
        }
    }

    @objc
    func selectCleanupModel(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? CleanupModelOption else { return }
        updateConfig { config in
            switch option.provider {
            case .anthropic:
                config.anthropicModel = option.id
            case .openAI:
                config.openAIModel = option.id
            }
        }
    }

    private func title(for provider: CleanupProvider) -> String {
        switch provider {
        case .anthropic:
            return "Anthropic"
        case .openAI:
            return "OpenAI"
        }
    }
}
