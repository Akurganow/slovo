/// Which edge of the push-to-talk hotkey fired: `.down` starts a session carrying
/// the mode latched at the key-down edge, `.up` stops it while carrying the
/// session's final `DictationMode`, `.translateLatched` reports that Control latched
/// translate LIVE mid-hold so the recording glyph can switch before key-up, and
/// `.cancel` silently discards an in-flight session (a right-modifier combo
/// interrupted the hold).
public enum HotkeyPhase: Equatable, Sendable {
    case down(DictationMode)
    case up(DictationMode)
    case translateLatched
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
