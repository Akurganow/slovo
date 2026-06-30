import Foundation

/// A selectable cleanup model option for a specific cleanup provider.
public struct CleanupModelOption: Equatable, Sendable {
    public let provider: CleanupProvider
    public let id: String
    public let displayName: String

    public init(provider: CleanupProvider, id: String, displayName: String) {
        self.provider = provider
        self.id = id
        self.displayName = displayName
    }
}

/// Provider-specific model options exposed by the app UI.
public enum CleanupModelCatalog {
    public static func options(for provider: CleanupProvider) -> [CleanupModelOption] {
        switch provider {
        case .anthropic:
            return [
                CleanupModelOption(
                    provider: .anthropic,
                    id: Config.defaultAnthropicModel,
                    displayName: "Claude Haiku 4.5"
                ),
            ]
        case .openAI:
            return [
                CleanupModelOption(
                    provider: .openAI,
                    id: Config.defaultOpenAIModel,
                    displayName: "GPT-5.4 mini"
                ),
                CleanupModelOption(
                    provider: .openAI,
                    id: "gpt-5.4-nano",
                    displayName: "GPT-5.4 nano"
                ),
            ]
        }
    }
}
