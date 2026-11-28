import Foundation
import SlovoCore

public enum CleanupBenchmarkCandidateFactory {
    public static func makeCandidate(
        for spec: CleanupBenchmarkProviderSpec,
        environment: [String: String]
    ) throws -> CleanupBenchmarkCandidate {
        switch spec.provider {
        case .openRouter:
            let keyProvider = StaticCleanupKeyProvider(
                key: try key("OPENROUTER_API_KEY", in: environment)
            )
            let cleaner = CleanupRoute(
                providers: CleanupProviders(openRouterKeys: keyProvider),
                promptBuilder: PromptBuilder()
            )
            return CleanupBenchmarkCandidate(
                provider: spec.provider.rawValue, model: spec.model, lane: spec.lane, width: spec.width
            ) { raw, config, context, hints in
                var config = config
                config.provider = .openRouter
                let cleaned = try await cleaner.cleanReportingCost(raw, config: config, context: context, hints: hints)
                return CleanupBenchmarkCleaned(text: cleaned.text, costUSD: cleaned.costUSD)
            }
        case .passThrough:
            // No request is made, so the cost is known: nothing.
            return CleanupBenchmarkCandidate(
                provider: spec.provider.rawValue, model: spec.model, lane: spec.lane, width: spec.width
            ) { raw, config, context, _ in
                CleanupBenchmarkCleaned(text: try await PassThrough().clean(raw, config: config, context: context), costUSD: 0)
            }
        }
    }

    public static func key(_ name: String, in environment: [String: String]) throws -> String {
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

private struct StaticCleanupKeyProvider: OpenRouterKeyProvider {
    let key: String

    func apiKey() throws -> String {
        key
    }
}
