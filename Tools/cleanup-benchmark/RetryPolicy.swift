/// When to try a failed request again. Network errors and the statuses OpenRouter
/// documents as transient are retried; a 400 or a 401 never is.
enum CleanupBenchmarkRetryPolicy {
    enum Failure: Equatable {
        case status(Int, retryAfter: Double?)
        case network
    }

    static let attempts = 4
    private static let longestWait = 30.0

    /// Seconds to wait before the next attempt, or nil when the failure is final or
    /// the attempts (counted from 0) are used up.
    static func delay(after failure: Failure, attempt: Int) -> Double? {
        guard attempt + 1 < attempts else { return nil }
        switch failure {
        case .network:
            return backoff(attempt, retryAfter: nil)
        case .status(let status, let retryAfter):
            // OpenRouter's limits page names a transient 402 (`openrouter_in_flight_budget`)
            // that is retried after `Retry-After`: https://openrouter.ai/docs/api_reference/limits.md
            // (documentation, no published revision)
            guard [402, 429].contains(status) || status >= 500 else { return nil }
            return backoff(attempt, retryAfter: retryAfter)
        }
    }

    private static func backoff(_ attempt: Int, retryAfter: Double?) -> Double {
        min(retryAfter ?? Double(1 << attempt), longestWait)
    }
}
