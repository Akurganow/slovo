import Foundation
import LoquiCore

/// A deterministic, manually-advanced `Clock` for `ModelLifecycle` tests.
public final class FakeClock: Clock {
    private var current: TimeInterval

    public init(start: TimeInterval = 0) {
        current = start
    }

    public func advance(by seconds: TimeInterval) {
        current += seconds
    }

    public func now() -> TimeInterval {
        current
    }
}
