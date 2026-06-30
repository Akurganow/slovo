import Foundation

/// Rewrites a transcript via OpenAI's Responses API.
public struct OpenAICleaner: Cleaner {
    private let session: URLSession
    private let keyProvider: OpenAIKeyProvider
    private let promptBuilder: PromptBuilder
    private let log: RedactionSafeLog

    private static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    public init(
        session: URLSession,
        keyProvider: OpenAIKeyProvider,
        promptBuilder: PromptBuilder,
        log: RedactionSafeLog = RedactionSafeLog(subsystem: "loqui", category: "cleaner")
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
        let key: String
        do {
            key = try keyProvider.apiKey()
        } catch {
            throw CleanupError.missingKey
        }

        let prompt = promptBuilder.buildPrompt(raw: raw, config: config, context: context)
        let body = OpenAIRequest(
            model: prompt.model,
            instructions: prompt.systemBlocks.joined(separator: "\n\n"),
            input: prompt.input,
            store: false,
            maxOutputTokens: 4_096
        )
        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
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

        guard let decoded = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
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
