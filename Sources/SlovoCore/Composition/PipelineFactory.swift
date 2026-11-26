/// The composition root: assembles the single configured pipeline.
///
/// EXACTLY ONE injected `Transcriber` (the one configured WhisperKit transcriber —
/// no runtime multi-backend switch), one cleaner, one injector, one
/// personalization source. The cleaner is always wrapped in `FallbackCleaner`.
public enum PipelineFactory {
    /// Builds the orchestrator from the injected dependencies (production passes
    /// the real adapters; tests pass fakes).
    public static func makeOrchestrator(dependencies: Dependencies) -> Orchestrator {
        let fallback = FallbackCleaner(
            cleaner: dependencies.cleaner,
            statusReporter: { status in
                dependencies.reportStatus(status)
            },
            onCleanupFailure: dependencies.onCleanupFailure
        )
        var assembled = dependencies
        assembled.cleaner = fallback
        return Orchestrator(dependencies: assembled)
    }
}
