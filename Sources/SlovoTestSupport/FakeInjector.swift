import SlovoCore
import Synchronization

/// A programmable `Injector` fake for tests: it succeeds or throws exactly the
/// outcome it was constructed with, and records the text of every call. The call
/// log is `Mutex`-guarded so the fake is genuinely race-free under the actor.
public final class FakeInjector: Injector {
    /// What the fake should do when `insert` is invoked.
    public enum Outcome: Sendable {
        case success
        case failure(InjectionError)
    }

    private let recordedCalls = Mutex<[String]>([])
    private let outcome: Outcome

    public init(outcome: Outcome) {
        self.outcome = outcome
    }

    /// The text of every call, in invocation order.
    public var calls: [String] {
        recordedCalls.withLock { $0 }
    }

    public func insert(_ text: String) async throws {
        recordedCalls.withLock { $0.append(text) }
        switch outcome {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}
