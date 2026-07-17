/// Which edge of the push-to-talk hotkey fired: `.down` starts a session, `.up`
/// stops it while carrying the latched `DictationMode` for the session, `.cancel`
/// silently discards an in-flight session (a right-modifier combo interrupted the
/// hold).
public enum HotkeyPhase: Equatable, Sendable {
    case down
    case up(DictationMode)
    case cancel
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
