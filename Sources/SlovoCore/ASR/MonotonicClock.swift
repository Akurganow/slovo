import Foundation

/// Production `Clock`: monotonic process uptime, so keep-warm idle timing is not
/// perturbed by wall-clock adjustments.
///
/// Conformance is qualified `SlovoCore.Clock` so it binds to the injected
/// time-source seam and never to the standard library's `Clock`.
public struct MonotonicClock: SlovoCore.Clock {
    public init() {}

    public func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    public func sleep(for seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}
