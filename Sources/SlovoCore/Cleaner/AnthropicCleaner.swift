import Foundation

/// The default `Cleaner`: rewrites a transcript via the Anthropic Messages API
/// (spec §18.1, §18.3). SECURITY-CRITICAL — the privacy invariant is enforced
/// here:
///
/// - The API key reaches EXACTLY ONE use site: the `x-api-key` header. It is
///   never logged, stored in a readable property, or placed in an error.
/// - No payload (transcript, cleaned text, prompt, vocabulary, or the response
///   body) is ever logged. Log lines are fixed, coarse strings only.
/// - Fail-closed: exactly ONE outbound POST per `clean`. There is no retry loop —
///   recovery is the `FallbackCleaner` → `PassThrough` path, never a re-send that
///   would re-transmit the transcript.
public struct AnthropicCleaner: Cleaner {
    private let session: URLSession
    private let keyProvider: AnthropicKeyProvider
    private let promptBuilder: PromptBuilder
    private let log: RedactionSafeLog

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    public init(
        session: URLSession,
        keyProvider: AnthropicKeyProvider,
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
        // Key sourcing failure → missingKey (the key value never enters the error).
        let key: String
        do {
            key = try keyProvider.apiKey()
        } catch {
            throw CleanupError.missingKey
        }

        let request = promptBuilder.build(raw: raw, config: config, context: context)
        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")  // the ONLY key use site
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        // EXACTLY ONE POST — no retry loop (fail-closed; recovery is FallbackCleaner).
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
            // retry-after is a coarse control value (not a payload); parsed but NOT
            // acted on here (no in-cleaner retry).
            let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
            log.event("cleanup failed: rateLimited")
            throw CleanupError.rateLimited(retryAfter: retryAfter)
        }
        if http.statusCode >= 400 {
            // The error body can echo the transcript — decode for control flow only,
            // NEVER log it. Only the coarse status code (an Int) crosses into the error.
            log.event("cleanup failed: apiError")
            throw CleanupError.apiError(status: http.statusCode)
        }

        // A malformed 2xx body (undecodable, or missing content) must NOT escape as
        // a raw DecodingError — map it to a CleanupError so FallbackCleaner degrades
        // to PassThrough and the words are never lost. The body is NEVER logged.
        guard let decoded = try? JSONDecoder().decode(AnthropicResponse.self, from: data) else {
            log.event("cleanup failed: apiError")
            throw CleanupError.apiError(status: http.statusCode)
        }

        // Branch on refusal BEFORE reading content (a refusal has empty/partial
        // content — reading content[0] would crash). P12.
        if decoded.stopReason == "refusal" {
            log.event("cleanup failed: refused")
            throw CleanupError.refused
        }

        // Pick the text block by type, not by index (content[0] may be a non-text block).
        let cleaned = decoded.content.first { $0.type == "text" }?.text ?? ""
        // Coarse success line: a fixed string + the LENGTH only (never the text).
        log.event("cleanup ok")
        log.logLength(of: cleaned)
        return cleaned
    }
}
