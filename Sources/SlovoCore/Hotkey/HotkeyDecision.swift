/// The five keyboard-modifier bits the push-to-talk decision reads, abstracted
/// from `CGEventFlags` so the decision core stays free of the event tap. The tap
/// adapter maps the live `CGEventFlags` down to exactly these bits.
public struct HotkeyModifierFlags: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let secondaryFn = HotkeyModifierFlags(rawValue: 1 << 0)
    public static let command = HotkeyModifierFlags(rawValue: 1 << 1)
    public static let option = HotkeyModifierFlags(rawValue: 1 << 2)
    public static let control = HotkeyModifierFlags(rawValue: 1 << 3)
    public static let shift = HotkeyModifierFlags(rawValue: 1 << 4)
}

/// A tap event reduced to only what the decision needs. A `.keyDown` carries NO
/// key code and NO character: the interruption decision consumes only the fact
/// that *a* key was pressed, so keystroke content never reaches this layer
/// (privacy invariant).
public enum HotkeyInputEvent: Equatable, Sendable {
    case flagsChanged(keyCode: Int64, flags: HotkeyModifierFlags)
    case keyDown
    case tapDisabled
}

/// What the tap adapter must do with the current event. `suppress` is true only
/// for fn (its event is hidden from the OS); every other trigger passes through so
/// it keeps working as a normal modifier.
public enum HotkeyDecision: Equatable, Sendable {
    /// Start a session; `mode` is the intent latched at the key-down edge, so
    /// Control already held at key-down starts directly in `.translate`.
    case start(suppress: Bool, mode: DictationMode)
    case stop(suppress: Bool, mode: DictationMode)
    /// Control latched translate LIVE, mid-hold, on an event that otherwise passes
    /// through. Surfaced so the UI can switch the recording glyph the moment the
    /// latch engages instead of waiting for the stop edge. Fires at most once per
    /// session (the latch is one-way); the underlying event is passed through.
    case translateLatched
    /// A non-trigger key went down while a passthrough-modifier trigger was held: cancel
    /// the in-flight dictation silently; the real combo passes through untouched.
    case interruptCancel
    /// The tap was disabled; re-enable it. `synthesizeUp` is true when a trigger
    /// was believed held, so a stuck "down" is released.
    case resync(synthesizeUp: Bool)
    /// Nothing to do; pass the event through unchanged.
    case passThrough
}

/// The tap-free push-to-talk decision core. Maps each reduced input event to a
/// `HotkeyDecision` by composing a recognizer for the push-to-talk key, a
/// recognizer for the key that latches translate, and the session policy that
/// turns their answers into decisions — so the CGEventTap adapter stays a thin
/// translator with no policy of its own. It reads no clock and performs no I/O;
/// every piece of its state is updated deterministically on every path.
public struct HotkeyDecisionCore {
    /// One push-to-talk hold. The latched translate intent lives INSIDE it, so a
    /// latch without a hold is unrepresentable: an abnormal end (interrupt-cancel,
    /// tap death) takes any latched intent with it.
    private struct Session {
        /// Latched by the latch key at any moment of the hold, the key-down edge
        /// included. One-way while the hold lasts; consumed at the stop edge to
        /// pick `.translate` over `.plain`.
        var isTranslateLatched: Bool
    }

    /// Whether a push-to-talk hold is open.
    public var isTriggerHeld: Bool { session != nil }

    private var pushToTalkKey: TriggerRecognizer
    /// The key whose press latches translate. Fixed to Control, recognized by its
    /// modifier class alone: either Control key latches, so no side is
    /// disambiguated.
    private let latchKey = TriggerRecognizer(.classModifier(.control))
    private var session: Session?

    public init(trigger: HotkeyTrigger) {
        pushToTalkKey = TriggerRecognizer(trigger: trigger)
    }

    /// Applies a live trigger change, dropping any open hold so the next event is
    /// judged against a clean state.
    public mutating func reconfigure(to trigger: HotkeyTrigger) {
        pushToTalkKey = TriggerRecognizer(trigger: trigger)
        session = nil
    }

    public mutating func handle(_ event: HotkeyInputEvent) -> HotkeyDecision {
        switch event {
        case let .flagsChanged(keyCode, flags):
            return handleFlagsChanged(keyCode: keyCode, flags: flags)
        case .keyDown:
            // A key press while an interruptible trigger is held = the user reaching
            // for a shortcut, not dictating: cancel silently, the combo passes through.
            guard session != nil, pushToTalkKey.isInterruptible else { return .passThrough }
            session = nil
            return .interruptCancel
        case .tapDisabled:
            let wasHeld = session != nil
            session = nil
            return .resync(synthesizeUp: wasHeld)
        }
    }

    private mutating func handleFlagsChanged(keyCode: Int64, flags: HotkeyModifierFlags) -> HotkeyDecision {
        let suppress = pushToTalkKey.suppressesEvent
        guard var openSession = session else {
            guard pushToTalkKey.engages(keyCode: keyCode, flags: flags) else { return .passThrough }
            pushToTalkKey.recordEngage(keyCode: keyCode)
            // The latch key already held at key-down counts, so the start itself can
            // carry `.translate` and the recording glyph never flashes plain first.
            let isLatched = latchKey.engages(keyCode: keyCode, flags: flags)
            session = Session(isTranslateLatched: isLatched)
            return .start(suppress: suppress, mode: isLatched ? .translate : .plain)
        }
        // The latch is read BEFORE the trigger judges the event, so a foreign latch
        // key latches even though its own event is not the trigger's.
        let wasLatched = openSession.isTranslateLatched
        openSession.isTranslateLatched = wasLatched || latchKey.engages(keyCode: keyCode, flags: flags)
        guard !pushToTalkKey.releases(keyCode: keyCode, flags: flags) else {
            session = nil
            return .stop(suppress: suppress, mode: openSession.isTranslateLatched ? .translate : .plain)
        }
        session = openSession
        // A fresh mid-hold latch only ever coincides with an event that passes
        // through (the trigger is still held, so this is neither a start nor a stop);
        // surface it live so the recording glyph can switch without waiting for stop.
        if !wasLatched, openSession.isTranslateLatched { return .translateLatched }
        return .passThrough
    }
}
