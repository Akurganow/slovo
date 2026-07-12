/// A selectable routed cleanup model option.
public struct CleanupModelOption: Equatable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// OpenRouter model options exposed by the app UI.
public enum CleanupModelCatalog {
    public static var options: [CleanupModelOption] {
        openRouterOptions
    }

    public static func displayName(for model: String) -> String {
        options.first { $0.id == model }?.displayName ?? model
    }

    private static let openRouterOptions: [CleanupModelOption] = [
        CleanupModelOption(
            id: Config.defaultOpenRouterModel,
            displayName: "GPT-5.6 Luna"
        ),
        CleanupModelOption(
            id: "anthropic/claude-haiku-4.5",
            displayName: "Claude Haiku 4.5"
        ),
        CleanupModelOption(
            id: "google/gemini-3.1-flash-lite",
            displayName: "Gemini 3.1 Flash Lite"
        ),
        CleanupModelOption(
            id: "qwen/qwen3.6-flash",
            displayName: "Qwen3.6 Flash"
        ),
        CleanupModelOption(
            id: "deepseek/deepseek-v4-flash",
            displayName: "DeepSeek V4 Flash"
        ),
        CleanupModelOption(
            id: "mistralai/mistral-small-2603",
            displayName: "Mistral Small 4"
        ),
        CleanupModelOption(
            id: "minimax/minimax-m3",
            displayName: "MiniMax M3"
        ),
    ]
}
