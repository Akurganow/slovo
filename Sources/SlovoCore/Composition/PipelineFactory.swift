/// The composition root: assembles the single configured pipeline.
///
/// EXACTLY ONE injected `Transcriber` (the one configured WhisperKit transcriber —
/// no runtime multi-backend switch), a fallback cleaner chain, one injector, one
/// personalization source. Cleanup always wraps the configured upstream cleaner
/// before `PassThrough`.
public enum PipelineFactory {
    /// Builds the orchestrator from the injected dependencies (production passes
    /// the real adapters; tests pass fakes).
    public static func makeOrchestrator(
        config: Config,
        dependencies: Dependencies,
        cleanupConfig: CleanupConfig? = nil
    ) -> Orchestrator {
        let fallback = FallbackCleaner(
            chain: [dependencies.cleaner, PassThrough()],
            statusReporter: { status in
                dependencies.reportStatus(status)
            },
            onCleanupFailure: dependencies.onCleanupFailure
        )
        var assembled = dependencies
        assembled.cleaner = fallback
        return Orchestrator(
            dependencies: assembled,
            cleanupConfig: cleanupConfig ?? config.cleanupConfig,
            mutesSystemAudioWhileDictating: config.mutesSystemAudioWhileDictating,
            usesVocabularyBias: config.usesVocabularyBias
        )
    }
}
