import Foundation
import os

/// Reaches a cleanup model through OpenRouter's OpenAI-compatible Chat
/// Completions API.
struct OpenRouterProvider: CleanupProvider {
    // Internal so a test reads the session the init chose.
    let session: URLSession
    private let keyProvider: OpenRouterKeyProvider

    // Latency mark and failure sink for the post-key-up cleanup step, on the same
    // subsystem/category as the orchestrator and paste injector so one `log show`
    // predicate spans the whole key-up → inserted timeline. Carries the HTTP
    // status and durations, which only this transport knows; the route's
    // redaction-safe log carries the outcome.
    private static let diagnosticLog = Logger(subsystem: "com.slovo.app", category: "dictation")

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    // The resource timer bounds the whole request: an idle timer alone lets a trickling
    // reply hold the pipeline, and every press is refused until it ends. Both timers
    // take the one number so it states the request's deadline; the resource timer
    // alone already fires first. Apple's NSURLSession.h (macOS 27.2 SDK),
    // timeoutIntervalForResource: "The resource timer starts when the request is
    // initiated and counts until either the request completes or this timeout interval
    // is reached, whichever comes first."
    private static let cleanupSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = CleanupDefaults.deadline
        configuration.timeoutIntervalForResource = CleanupDefaults.deadline
        return URLSession(configuration: configuration)
    }()

    init(keyProvider: OpenRouterKeyProvider) {
        self.init(session: Self.cleanupSession, keyProvider: keyProvider)
    }

    // Internal so tests can pass a stub session.
    init(session: URLSession, keyProvider: OpenRouterKeyProvider) {
        self.session = session
        self.keyProvider = keyProvider
    }

    func reply(to prompt: CleanupPrompt) async throws -> CleanupReply {
        let key: String
        do {
            key = try keyProvider.apiKey()
        } catch {
            let failure = CleanupError.missingKey
            Self.logFailure(failureKind: failure.logToken, failureStatus: "none", failureMs: 0)
            throw failure
        }

        let body = OpenRouterRequest(
            model: prompt.model,
            messages: [
                OpenRouterRequest.Message(role: "system", content: prompt.systemText),
                OpenRouterRequest.Message(role: "user", content: prompt.input),
            ],
            temperature: 0,
            // Cleanup is a constrained rewrite; provider-default reasoning (on for
            // some catalog models) only adds key-up latency.
            reasoning: OpenRouterRequest.Reasoning(effort: "none")
        )
        var urlRequest = URLRequest(url: Self.endpoint)
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
        } catch let error as URLError {
            let failure = Self.transportFailure(error)
            Self.logFailure(
                failureKind: failure.logToken,
                failureStatus: "none",
                failureMs: Self.elapsedMs(since: requestStartUptime)
            )
            throw failure
        }
        let requestMs = Self.elapsedMs(since: requestStartUptime)
        Self.diagnosticLog.info(
            """
            cleanup.request ms=\(requestMs, privacy: .public)
            """
        )

        guard let http = response as? HTTPURLResponse else {
            let failure = CleanupError.badResponse
            Self.logFailure(failureKind: failure.logToken, failureStatus: "none", failureMs: requestMs)
            throw failure
        }

        if http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
            let failure = CleanupError.rateLimited(retryAfter: retryAfter)
            Self.logFailure(failureKind: failure.logToken, failureStatus: "\(http.statusCode)", failureMs: requestMs)
            throw failure
        }
        if http.statusCode >= 400 {
            let failure = http.statusCode == 404 ? CleanupError.modelUnavailable : CleanupError.refused
            Self.logFailure(failureKind: failure.logToken, failureStatus: "\(http.statusCode)", failureMs: requestMs)
            throw failure
        }

        guard let decoded = try? JSONDecoder().decode(OpenRouterResponse.self, from: data),
              let cleaned = decoded.firstText
        else {
            // Its own word, not `.noText`'s "apiError": the readable line tells an
            // unreadable reply from a refusal.
            Self.logFailure(failureKind: "undecodable", failureStatus: "\(http.statusCode)", failureMs: requestMs)
            throw CleanupError.noText
        }

        return CleanupReply(text: cleaned, costUSD: decoded.cost)
    }

    /// Names a cleanup failure on the readable log: which failure, the provider's
    /// HTTP status when it answered, and how long the attempt took. The route's
    /// outcome lines are redacted, and `cleanup.request` is emitted before the
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

    private static func transportFailure(_ error: URLError) -> CleanupError {
        switch error.code {
        case .timedOut:
            .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .callIsActive:
            .offline
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected:
            .tls
        default:
            .transport
        }
    }

    private static func elapsedMs(since startUptime: TimeInterval) -> Int {
        Int((ProcessInfo.processInfo.systemUptime - startUptime) * 1_000)
    }
}
