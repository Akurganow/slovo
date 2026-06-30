import Foundation

/// A description of what the composition root wired, so AC-1 can assert the shape
/// without reaching into private fields.
public struct CompositionSummary: Sendable, Equatable {
    public let transcriberCount: Int
    public let cleanerIsFallback: Bool
    /// The fallback chain's cleaner kinds, in order (e.g. `["AnthropicCleaner", "PassThrough"]`).
    public let fallbackChainKinds: [String]
    public let injectorCount: Int
    public let sourceCount: Int

    public init(
        transcriberCount: Int,
        cleanerIsFallback: Bool,
        fallbackChainKinds: [String],
        injectorCount: Int,
        sourceCount: Int
    ) {
        self.transcriberCount = transcriberCount
        self.cleanerIsFallback = cleanerIsFallback
        self.fallbackChainKinds = fallbackChainKinds
        self.injectorCount = injectorCount
        self.sourceCount = sourceCount
    }
}

/// The composition root (spec §18.2): assembles the single configured pipeline.
///
/// EXACTLY ONE `Transcriber` (the bake-off winner via `TranscriberFactory` — no
/// runtime multi-backend switch), a fallback cleaner chain, one injector, one
/// personalization source. Enabled cleanup wraps the configured upstream cleaner
/// before `PassThrough`; disabled cleanup is `PassThrough` only.
public enum PipelineFactory {
    /// Builds the orchestrator from the injected dependencies (production passes
    /// the real adapters; tests pass fakes).
    public static func makeOrchestrator(
        config: Config,
        dependencies: Dependencies,
        vocabularyLimit: Int = 50
    ) -> Orchestrator {
        let assembly = assemble(config: config, dependencies: dependencies)
        return Orchestrator(
            dependencies: assembly.dependencies,
            cleanupConfig: config.cleanupConfig,
            vocabularyLimit: vocabularyLimit
        )
    }

    /// The composition shape this factory produces — one transcriber, a fallback
    /// cleaner chain, one injector, one source. Enabled cleanup wraps the
    /// configured upstream cleaner before `PassThrough`; disabled cleanup is
    /// `PassThrough` only. A multi-backend switch would be wrong.
    public static func describeComposition(config: Config, dependencies: Dependencies) -> CompositionSummary {
        assemble(config: config, dependencies: dependencies).summary
    }

    private struct Assembly: Sendable {
        let dependencies: Dependencies
        let summary: CompositionSummary
    }

    private static func assemble(config: Config, dependencies: Dependencies) -> Assembly {
        let fallbackChain: [any Cleaner] = config.cleanupEnabled
            ? [dependencies.cleaner, PassThrough()]
            : [PassThrough()]
        let fallback = FallbackCleaner(
            chain: fallbackChain,
            statusReporter: { status in
                dependencies.reportStatus(status)
            }
        )
        var assembled = dependencies
        assembled.cleaner = fallback

        return Assembly(
            dependencies: assembled,
            summary: CompositionSummary(
                transcriberCount: 1,
                cleanerIsFallback: true,
                fallbackChainKinds: fallbackChain.map(typeName),
                injectorCount: 1,
                sourceCount: 1
            )
        )
    }

    private static func typeName(of value: any Cleaner) -> String {
        String(describing: Swift.type(of: value))
    }
}
