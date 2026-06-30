import Foundation
import SlovoCore

/// A `HotkeyMonitor` fake that lets a test drive hotkey edges synthetically and
/// records how often it was started and stopped.
public final class FakeHotkeyMonitor: HotkeyMonitor {
    public var onTrigger: ((HotkeyPhase) -> Void)?

    public private(set) var startCount = 0
    public private(set) var stopCount = 0

    public init() {}

    public func start() throws {
        startCount += 1
    }

    public func stop() {
        stopCount += 1
    }

    /// Synthetically fires a hotkey edge through `onTrigger`.
    public func fire(_ phase: HotkeyPhase) {
        onTrigger?(phase)
    }
}
