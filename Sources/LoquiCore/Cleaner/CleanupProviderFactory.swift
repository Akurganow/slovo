import Foundation

/// Builds provider-specific cleanup dependencies from the selected cleanup provider.
public enum CleanupProviderFactory {
    public static func makeCleaner(
        for provider: CleanupProvider,
        session: URLSession = .shared,
        anthropicKeyProvider: any AnthropicKeyProvider,
        openAIKeyProvider: any OpenAIKeyProvider,
        promptBuilder: PromptBuilder,
        log: RedactionSafeLog = RedactionSafeLog(subsystem: "loqui", category: "cleaner")
    ) -> any Cleaner {
        switch provider {
        case .anthropic:
            return AnthropicCleaner(
                session: session,
                keyProvider: anthropicKeyProvider,
                promptBuilder: promptBuilder,
                log: log
            )
        case .openAI:
            return OpenAICleaner(
                session: session,
                keyProvider: openAIKeyProvider,
                promptBuilder: promptBuilder,
                log: log
            )
        }
    }

    public static func selectedKeyProvider(
        for provider: CleanupProvider,
        anthropicKeyProvider: any CleanupKeyProvider,
        openAIKeyProvider: any CleanupKeyProvider
    ) -> any CleanupKeyProvider {
        switch provider {
        case .anthropic:
            return anthropicKeyProvider
        case .openAI:
            return openAIKeyProvider
        }
    }
}
