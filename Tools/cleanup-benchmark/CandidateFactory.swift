import Foundation
import SlovoCore

public enum CleanupBenchmarkCandidateFactory {
    public static func makeCandidate(
        for spec: CleanupBenchmarkProviderSpec,
        environment: [String: String]
    ) throws -> CleanupBenchmarkCandidate {
        switch spec.provider {
        case .anthropic:
            let keyProvider = StaticCleanupKeyProvider(
                key: try key("ANTHROPIC_API_KEY", in: environment)
            )
            return CleanupBenchmarkCandidate(
                provider: spec.provider.rawValue,
                model: spec.model,
                cleaner: CleanupProviderFactory.makeCleaner(
                    for: .anthropic,
                    session: .shared,
                    anthropicKeyProvider: keyProvider,
                    openAIKeyProvider: StaticCleanupKeyProvider(key: ""),
                    promptBuilder: PromptBuilder(maxVocabularyTerms: 50)
                )
            )
        case .openAI:
            let keyProvider = StaticCleanupKeyProvider(
                key: try key("OPENAI_API_KEY", in: environment)
            )
            return CleanupBenchmarkCandidate(
                provider: spec.provider.rawValue,
                model: spec.model,
                cleaner: CleanupProviderFactory.makeCleaner(
                    for: .openAI,
                    session: .shared,
                    anthropicKeyProvider: StaticCleanupKeyProvider(key: ""),
                    openAIKeyProvider: keyProvider,
                    promptBuilder: PromptBuilder(maxVocabularyTerms: 50)
                )
            )
        case .passThrough:
            return CleanupBenchmarkCandidate(
                provider: spec.provider.rawValue,
                model: spec.model,
                cleaner: PassThrough()
            )
        }
    }

    private static func key(_ name: String, in environment: [String: String]) throws -> String {
        guard let key = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else {
            throw CleanupBenchmarkCandidateFactoryError.missingEnvironmentKey(name)
        }
        return key
    }
}

public enum CleanupBenchmarkCandidateFactoryError: Error, Equatable, Sendable {
    case missingEnvironmentKey(String)
}

private struct StaticCleanupKeyProvider: AnthropicKeyProvider, OpenAIKeyProvider {
    let key: String

    func apiKey() throws -> String {
        key
    }
}
