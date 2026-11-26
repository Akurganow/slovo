/// The cleaner the app and the benchmark build: picks the provider the config
/// names, sends it the prompt and logs the outcome. Fallback to the spoken text
/// is `FallbackCleaner`'s job, so the benchmark sees every failure.
public struct CleanupRoute: Cleaner {
    private let providers: CleanupProviders
    private let promptBuilder: PromptBuilder
    private let log: RedactionSafeLog

    public init(
        providers: CleanupProviders,
        promptBuilder: PromptBuilder,
        log: RedactionSafeLog = RedactionSafeLog(subsystem: "slovo", category: "cleaner")
    ) {
        self.providers = providers
        self.promptBuilder = promptBuilder
        self.log = log
    }

    public func clean(
        _ raw: String,
        config: CleanupConfig,
        context: PersonalizationContext
    ) async throws -> String {
        try await clean(raw, config: config, context: context, hints: CleanupHints())
    }

    public func clean(
        _ raw: String,
        config: CleanupConfig,
        context: PersonalizationContext,
        hints: CleanupHints
    ) async throws -> String {
        try await cleanReportingCost(raw, config: config, context: context, hints: hints).text
    }

    /// `clean` plus the cost the provider charged, nil when it names none.
    /// Its one caller outside the app is the cleanup benchmark, which reports what cleanup costs.
    public func cleanReportingCost(
        _ raw: String,
        config: CleanupConfig,
        context: PersonalizationContext,
        hints: CleanupHints
    ) async throws -> CleanupReply {
        let prompt = promptBuilder.buildPrompt(raw: raw, config: config, context: context, hints: hints)
        let reply: CleanupReply
        do {
            reply = try await providers.provider(for: config.provider).reply(to: prompt)
            // The check is the route's, so every adapter shares it. Never trim: the
            // model's text is returned as it is.
            guard reply.text.hasVisibleCharacter else { throw CleanupError.noText }
        } catch let error as CleanupError {
            // A missing key writes no outcome line: the readable `cleanup.failure` line names it.
            if case .missingKey = error { throw error }
            log.event("cleanup failed: \(error.logToken)")
            throw error
        }
        log.event("cleanup ok")
        log.logLength(of: reply.text)
        return reply
    }
}
