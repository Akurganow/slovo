import Foundation
import os

/// Rewrites a transcript through OpenRouter's OpenAI-compatible Chat
/// Completions API.
public struct OpenRouterCleaner: Cleaner {
    private let session: URLSession
    private let keyProvider: OpenRouterKeyProvider
    private let promptBuilder: PromptBuilder
    private let log: RedactionSafeLog

    // Latency mark sink for the post-key-up cleanup step, on the same
    // subsystem/category as the orchestrator and paste injector so one `log show`
    // predicate spans the whole key-up → inserted timeline. Distinct from `log`
    // (redaction-safe cleanup outcomes) by role; carries a duration only.
    private static let diagnosticLog = Logger(subsystem: "com.slovo.app", category: "dictation")

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
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
            Self.logFailure(failureKind: "missingKey", failureStatus: "none", failureMs: 0)
            throw CleanupError.missingKey
        }

        let prompt = promptBuilder.buildPrompt(raw: raw, config: config, context: context, hints: hints)
        let body = OpenRouterRequest(
            model: prompt.model,
            messages: [
                OpenRouterRequest.Message(role: "system", content: prompt.systemBlocks.joined(separator: "\n\n")),
                OpenRouterRequest.Message(role: "user", content: prompt.input),
            ],
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
        urlRequest.setValue("https://github.com/Akurganow/slovo", forHTTPHeaderField: "HTTP-Referer")
        urlRequest.setValue("Slovo", forHTTPHeaderField: "X-Title")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        // Latency mark: the OpenRouter round-trip — the network portion of the
        // post-key-up cleanup step, timed around the existing `data` await and
        // emitted once the request completes.
        let requestStartUptime = ProcessInfo.processInfo.systemUptime
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch is URLError {
            log.event("cleanup failed: offline")
            Self.logFailure(
                failureKind: "offline",
                failureStatus: "none",
                failureMs: Self.elapsedMs(since: requestStartUptime)
            )
            throw CleanupError.offline
        }
        let requestMs = Self.elapsedMs(since: requestStartUptime)
        Self.diagnosticLog.info(
            """
            cleanup.request ms=\(requestMs, privacy: .public)
            """
        )

        guard let http = response as? HTTPURLResponse else {
            log.event("cleanup failed: offline")
            Self.logFailure(failureKind: "offline", failureStatus: "none", failureMs: requestMs)
            throw CleanupError.offline
        }

        if http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
            log.event("cleanup failed: rateLimited")
            Self.logFailure(failureKind: "rateLimited", failureStatus: "\(http.statusCode)", failureMs: requestMs)
            throw CleanupError.rateLimited(retryAfter: retryAfter)
        }
        if http.statusCode >= 400 {
            log.event("cleanup failed: apiError")
            Self.logFailure(failureKind: "apiError", failureStatus: "\(http.statusCode)", failureMs: requestMs)
            throw CleanupError.apiError(status: http.statusCode)
        }

        guard let decoded = try? JSONDecoder().decode(OpenRouterResponse.self, from: data),
              let cleaned = decoded.firstText
        else {
            log.event("cleanup failed: apiError")
            Self.logFailure(failureKind: "undecodable", failureStatus: "\(http.statusCode)", failureMs: requestMs)
            throw CleanupError.apiError(status: http.statusCode)
        }

        log.event("cleanup ok")
        log.logLength(of: cleaned)
        return cleaned
    }

    /// Names a cleanup failure on the readable log: which failure, the provider's
    /// HTTP status when it answered, and how long the attempt took. The outcome
    /// lines on `log` are redacted, and `cleanup.request` is emitted before the
    /// status is known, so without this a refused or rate-limited request reads
    /// exactly like a fast success. The response body, the prompt, the transcript
    /// and the key never reach here.
    private static func logFailure(failureKind: String, failureStatus: String, failureMs: Int) {
        diagnosticLog.error(
            """
            cleanup.failure kind=\(failureKind, privacy: .public) \
            status=\(failureStatus, privacy: .public) ms=\(failureMs, privacy: .public)
            """
        )
    }

    private static func elapsedMs(since startUptime: TimeInterval) -> Int {
        Int((ProcessInfo.processInfo.systemUptime - startUptime) * 1_000)
    }
}
