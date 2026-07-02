import Foundation
import SlovoCore
import Synchronization

/// A deterministic, manually-advanced `Clock` for lifecycle/release tests.
///
/// `sleep(for:)` parks the caller on a continuation keyed to a deadline; the test
/// drives release timing with `advance(by:)`, which resumes every sleeper whose
/// deadline has now passed — no real time, no `Task.sleep`. It is cancellation-
/// aware (a cancelled sleep throws `CancellationError` and is removed), matching
/// the real `Task.sleep`. `Mutex`-guarded so the clock is safe to share between the
/// test and the transcriber actor.
///
/// Qualified as `SlovoCore.Clock` so it binds to the injected time-source seam and
/// never to the standard library's `Clock`.
public final class FakeClock: SlovoCore.Clock {
    private struct Sleeper {
        let id: UInt64
        let deadline: TimeInterval
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct State {
        var current: TimeInterval
        var sleepers: [Sleeper] = []
        var nextId: UInt64 = 0
    }

    private let state: Mutex<State>

    public init(start: TimeInterval = 0) {
        state = Mutex(State(current: start))
    }

    /// Advances virtual time and resumes every sleeper whose deadline has passed.
    public func advance(by seconds: TimeInterval) {
        let due: [CheckedContinuation<Void, Error>] = state.withLock { current in
            current.current += seconds
            let now = current.current
            let ready = current.sleepers.filter { $0.deadline <= now }
            current.sleepers.removeAll { $0.deadline <= now }
            return ready.map(\.continuation)
        }
        due.forEach { $0.resume() }
    }

    public func now() -> TimeInterval {
        state.withLock { $0.current }
    }

    public func sleep(for seconds: TimeInterval) async throws {
        try Task.checkCancellation()
        guard seconds > 0 else { return }
        let id = state.withLock { current -> UInt64 in
            defer { current.nextId += 1 }
            return current.nextId
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let resumeCancelled: (() -> Void)? = state.withLock { current in
                    if Task.isCancelled {
                        return { continuation.resume(throwing: CancellationError()) }
                    }
                    current.sleepers.append(
                        Sleeper(id: id, deadline: current.current + seconds, continuation: continuation)
                    )
                    return nil
                }
                resumeCancelled?()
            }
        } onCancel: {
            let continuation = state.withLock { current -> CheckedContinuation<Void, Error>? in
                guard let index = current.sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return current.sleepers.remove(at: index).continuation
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    /// Suspends until at least one sleeper has parked, or relents after a bounded
    /// yield budget (used to avoid advancing before the release task has scheduled
    /// its sleep).
    public func waitForSleeper(maxYields: Int = 500) async {
        for _ in 0..<maxYields {
            if state.withLock({ !$0.sleepers.isEmpty }) {
                return
            }
            await Task.yield()
        }
    }
}
