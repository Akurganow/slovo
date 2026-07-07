/// Which edge of the push-to-talk hotkey fired: `.down` starts a session,
/// `.up` stops it.
public enum HotkeyPhase: Equatable, Sendable {
    case down
    case up
}

/// The Start/Stop source. The real `CGEventTap` implementation is hardware-only;
/// this seam keeps the wiring testable with a synthetic driver.
public protocol HotkeyMonitor {
    /// Installs the tap / monitor.
    func start() throws
    /// Tears it down.
    func stop()
    /// Invoked on each hotkey edge; `.down` ⇒ Start, `.up` ⇒ Stop.
    var onTrigger: ((HotkeyPhase) -> Void)? { get set }
}
