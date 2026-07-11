import SlovoCore
import Synchronization

/// A programmable `Cleaner` fake for tests: it returns or throws exactly the
/// outcome it was constructed with, and records every call it received. The call
/// log is `Mutex`-guarded so the fake is genuinely race-free under the actor.
public final class FakeCleaner: Cleaner {
    /// What the fake should do when `clean` is invoked.
    public enum Outcome: Sendable {
        case success(String)
        case failure(CleanupError)
    }

    public struct Call: Sendable {
        public let raw: String
        public let config: CleanupConfig
        public let context: PersonalizationContext
        public let hints: CleanupHints
    }

    private let recordedCalls = Mutex<[Call]>([])
    private let outcome: Outcome

    public init(outcome: Outcome) {
        self.outcome = outcome
    }

    /// Every call's arguments, in invocation order.
    public var calls: [Call] {
        recordedCalls.withLock { $0 }
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
        recordedCalls.withLock { $0.append(Call(raw: raw, config: config, context: context, hints: hints)) }
        switch outcome {
        case .success(let cleaned):
            return cleaned
        case .failure(let error):
            throw error
        }
    }
}
