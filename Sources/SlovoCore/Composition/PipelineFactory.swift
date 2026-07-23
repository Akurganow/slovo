/// A description of what the composition root wired, so tests can assert the
/// shape without reaching into private fields.
public struct CompositionSummary: Sendable, Equatable {
    public let transcriberCount: Int
    public let cleanerIsFallback: Bool
    /// The fallback chain's cleaner kinds, in order.
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

/// The composition root: assembles the single configured pipeline.
///
/// EXACTLY ONE injected `Transcriber` (the system Speech runtime — no runtime
/// multi-backend switch), a fallback cleaner chain, one injector, one
/// personalization source. Cleanup always wraps the configured upstream cleaner
/// before `PassThrough`.
public enum PipelineFactory {
    /// Builds the orchestrator from the injected dependencies (production passes
    /// the real adapters; tests pass fakes).
    public static func makeOrchestrator(
        config: Config,
        dependencies: Dependencies,
        vocabularyLimit: Int = 50,
        cleanupConfig: CleanupConfig? = nil
    ) -> Orchestrator {
        let assembly = assemble(config: config, dependencies: dependencies)
        return Orchestrator(
            dependencies: assembly.dependencies,
            cleanupConfig: cleanupConfig ?? config.cleanupConfig,
            mutesSystemAudioWhileDictating: config.mutesSystemAudioWhileDictating,
            vocabularyLimit: vocabularyLimit
        )
    }

    /// The composition shape this factory produces — one transcriber, a fallback
    /// cleaner chain, one injector, one source. Cleanup always wraps the
    /// configured upstream cleaner before `PassThrough`. A multi-backend switch
    /// would be wrong.
    public static func describeComposition(config: Config, dependencies: Dependencies) -> CompositionSummary {
        assemble(config: config, dependencies: dependencies).summary
    }

    private struct Assembly: Sendable {
        let dependencies: Dependencies
        let summary: CompositionSummary
    }

    private static func assemble(config: Config, dependencies: Dependencies) -> Assembly {
        let fallbackChain: [any Cleaner] = [dependencies.cleaner, PassThrough()]
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
