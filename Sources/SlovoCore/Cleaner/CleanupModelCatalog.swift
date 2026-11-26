/// A selectable routed cleanup model option.
public struct CleanupModelOption: Equatable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// The model options the app UI offers, one list per provider.
public enum CleanupModelCatalog {
    public static func options(for provider: CleanupProviderID) -> [CleanupModelOption] {
        switch provider {
        case .openRouter: openRouterOptions
        }
    }

    public static func displayName(for model: String) -> String {
        CleanupProviderID.allCases
            .lazy.flatMap { options(for: $0) }
            .first { $0.id == model }?.displayName ?? model
    }

    private static let openRouterOptions: [CleanupModelOption] = [
        CleanupModelOption(
            id: Config.defaultOpenRouterModel,
            displayName: "GPT-6 Luna"
        ),
        CleanupModelOption(
            id: "anthropic/claude-haiku-5.5",
            displayName: "Claude Haiku 5.5"
        ),
        CleanupModelOption(
            id: "xiaomi/mimo-v2.6-flash",
            displayName: "MiMo V2.6 Flash"
        ),
        CleanupModelOption(
            id: "qwen/qwen3.8-flash",
            displayName: "Qwen3.8 Flash"
        ),
        CleanupModelOption(
            id: "deepseek/deepseek-v4.1-flash",
            displayName: "DeepSeek V4.1 Flash"
        ),
    ]
}
