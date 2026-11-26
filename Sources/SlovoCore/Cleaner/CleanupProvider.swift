/// One way to reach a cleanup model. An adapter maps the prompt to its own
/// request format and sampling settings, sends it over its own transport,
/// enforces `CleanupDefaults.deadline`, and maps every failure to
/// `CleanupError`.
public protocol CleanupProvider: Sendable {
    /// The model's answer to `prompt`, as it came. Throws `CleanupError` for
    /// every failure of the provider; any other error is a defect and reaches
    /// the orchestrator's unexpected-error path.
    func reply(to prompt: CleanupPrompt) async throws -> CleanupReply
}

public struct CleanupReply: Equatable, Sendable {
    public let text: String
    /// What the request cost in US dollars; nil when the provider names none.
    public let costUSD: Double?

    public init(text: String, costUSD: Double? = nil) {
        self.text = text
        self.costUSD = costUSD
    }
}

/// Every cleanup adapter of this build, one per provider tag. Built once per
/// composition, so an adapter may hold a connection.
public struct CleanupProviders: Sendable {
    private let openRouter: any CleanupProvider

    public init(openRouterKeys: any OpenRouterKeyProvider) {
        self.init(openRouter: OpenRouterProvider(keyProvider: openRouterKeys))
    }

    init(openRouter: any CleanupProvider) {
        self.openRouter = openRouter
    }

    func provider(for id: CleanupProviderID) -> any CleanupProvider {
        switch id {
        case .openRouter: openRouter
        }
    }
}
