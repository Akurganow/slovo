/// Wraps one `Cleaner` and, on any `CleanupError`, reports the failure and
/// returns the spoken text. A non-`CleanupError` (e.g. a request body that
/// fails to encode) is not caught here: it propagates to the orchestrator,
/// which inserts the spoken text.
///
/// Every expected `CleanupError` falls back WITH a user-visible sad-to-fail status.
/// Cleanup is always attempted upstream; preserving the user's voice-to-text
/// intent is non-negotiable. The decision is a no-`default` switch so a future
/// `CleanupError` case forces a deliberate visibility choice.
/// `@unchecked Sendable` because of the `statusReporter` closure: it is invoked
/// only synchronously from within `clean(...)` (never concurrently), and keeping
/// it a plain closure lets existing tests pass an ordinary capturing reporter (a
/// `@Sendable` reporter would forbid that). The wrapped `Cleaner` is genuinely
/// `Sendable`. The `onCleanupFailure` observer, like `statusReporter`, is invoked
/// only synchronously from within `clean(...)`.
public struct FallbackCleaner: Cleaner, @unchecked Sendable {
    private let cleaner: any Cleaner
    private let statusReporter: (StatusMessage) -> Void
    private let onCleanupFailure: ((CleanupError) -> Void)?

    public init(
        cleaner: any Cleaner,
        statusReporter: @escaping (StatusMessage) -> Void,
        onCleanupFailure: ((CleanupError) -> Void)? = nil
    ) {
        self.cleaner = cleaner
        self.statusReporter = statusReporter
        self.onCleanupFailure = onCleanupFailure
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
        do {
            return try await cleaner.clean(raw, config: config, context: context, hints: hints)
        } catch let error as CleanupError {
            report(error)
            onCleanupFailure?(error)
            return raw
        }
    }

    /// Every `CleanupError` reports that the spoken text was inserted. The
    /// no-`default` switch makes a new `CleanupError` case a compile error here.
    private func report(_ error: CleanupError) {
        switch error {
        case .missingKey, .timedOut, .offline, .tls, .transport, .badResponse,
             .rateLimited, .modelUnavailable, .refused, .noText:
            statusReporter(.cleanupUnavailableInsertedAsSpoken)
        }
    }
}
