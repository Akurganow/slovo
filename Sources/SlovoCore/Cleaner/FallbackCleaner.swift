/// A composite `Cleaner` that walks a chain, advancing to the next cleaner on any
/// `CleanupError` and terminating at `PassThrough` (spec §11, §18.3). A
/// non-`CleanupError` (e.g. `CancellationError`) PROPAGATES — it is never
/// swallowed and silently degraded.
///
/// Every expected `CleanupError` advances WITH a user-visible sad-to-fail status.
/// Cleanup is optional; preserving the user's voice-to-text intent is not. The
/// decision is a no-`default` switch so a future `CleanupError` case forces a
/// deliberate visibility choice.
/// `@unchecked Sendable` because of the `statusReporter` closure: it is invoked
/// only synchronously from within `clean(...)` (never concurrently), and keeping
/// it a plain closure lets existing tests pass an ordinary capturing reporter (a
/// `@Sendable` reporter would forbid that). The chain of `Cleaner`s is genuinely
/// `Sendable`.
public struct FallbackCleaner: Cleaner, @unchecked Sendable {
    private let chain: [any Cleaner]
    private let statusReporter: (StatusMessage) -> Void

    public init(chain: [any Cleaner], statusReporter: @escaping (StatusMessage) -> Void) {
        self.chain = chain
        self.statusReporter = statusReporter
    }

    public func clean(
        _ raw: String,
        config: CleanupConfig,
        context: PersonalizationContext
    ) async throws -> String {
        var lastError: CleanupError?
        for cleaner in chain {
            do {
                return try await cleaner.clean(raw, config: config, context: context)
            } catch let error as CleanupError {
                // Only CleanupError degrades; report the visible cases, then advance.
                report(error)
                lastError = error
                continue
            }
            // A non-CleanupError is NOT caught here, so it propagates out.
        }
        // The chain should end in PassThrough (which never throws); if a chain was
        // built without a terminal cleaner, surface the last degradation.
        if let lastError {
            throw lastError
        }
        return raw
    }

    /// Surfaces a user-visible status for the cases that warrant one. The
    /// no-`default` switch makes a new `CleanupError` case a compile error here.
    private func report(_ error: CleanupError) {
        switch error {
        case .offline, .missingKey, .rateLimited, .apiError:
            statusReporter(.cleanupUnavailableInsertedAsSpoken)
        case .refused:
            statusReporter(.cleanupUnavailableInsertedAsSpoken)
        }
    }
}
