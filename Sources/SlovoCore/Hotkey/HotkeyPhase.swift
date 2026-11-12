/// Which edge of the push-to-talk hotkey fired: `.down` starts a session carrying
/// the intent known at the key-down edge — an additional translate key already
/// held, or a standalone translate key opening the session itself — `.up` stops it
/// while carrying the session's final `DictationMode`, `.translateLatched` reports
/// that the additional translate key latched translate LIVE mid-hold so the
/// recording glyph can switch before key-up, and `.cancel` silently discards an
/// in-flight session (a passthrough-modifier combo interrupted the hold).
public enum HotkeyPhase: Equatable, Sendable {
    case down(DictationMode)
    case up(DictationMode)
    case translateLatched
    case cancel
}
