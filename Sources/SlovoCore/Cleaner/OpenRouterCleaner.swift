import Foundation

/// Rewrites a transcript through OpenRouter's OpenAI-compatible Chat
/// Completions API.
public struct OpenRouterCleaner: Cleaner {
    private let session: URLSession
    private let keyProvider: OpenRouterKeyProvider
    private let promptBuilder: PromptBuilder
    private let log: RedactionSafeLog

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private static let maxCleanupTokens = 1_024
    private static let requestTimeout: TimeInterval = 30

    public init(
        session: URLSession,
        keyProvider: OpenRouterKeyProvider,
        promptBuilder: PromptBuilder,
        log: RedactionSafeLog = RedactionSafeLog(subsystem: "slovo", category: "cleaner")
    ) {
        self.session = session
        self.keyProvider = keyProvider
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
        let key: String
        do {
            key = try keyProvider.apiKey()
        } catch {
            throw CleanupError.missingKey
        }

        let prompt = promptBuilder.buildPrompt(raw: raw, config: config, context: context, hints: hints)
        let body = OpenRouterRequest(
            model: prompt.model,
            messages: [
                OpenRouterRequest.Message(role: "system", content: prompt.systemBlocks.joined(separator: "\n\n")),
                OpenRouterRequest.Message(role: "user", content: prompt.input),
            ],
            maxTokens: Self.maxCleanupTokens,
            temperature: 0,
            // Cleanup is a constrained rewrite; provider-default reasoning (on for
            // some catalog models) only adds key-up latency.
            reasoning: OpenRouterRequest.Reasoning(effort: "none")
        )
        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.timeoutInterval = Self.requestTimeout
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue("https://github.com/slovo-app/slovo", forHTTPHeaderField: "HTTP-Referer")
        urlRequest.setValue("Slovo", forHTTPHeaderField: "X-Title")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch is URLError {
            log.event("cleanup failed: offline")
            throw CleanupError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            log.event("cleanup failed: offline")
            throw CleanupError.offline
        }

        if http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
            log.event("cleanup failed: rateLimited")
            throw CleanupError.rateLimited(retryAfter: retryAfter)
        }
        if http.statusCode >= 400 {
            log.event("cleanup failed: apiError")
            throw CleanupError.apiError(status: http.statusCode)
        }

        guard let decoded = try? JSONDecoder().decode(OpenRouterResponse.self, from: data),
              let cleaned = decoded.firstText
        else {
            log.event("cleanup failed: apiError")
            throw CleanupError.apiError(status: http.statusCode)
        }

        log.event("cleanup ok")
        log.logLength(of: cleaned)
        return cleaned
    }
}
