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
    /// Start a session; `mode` is the intent known at the key-down edge — an
    /// additional translate key already held, or a standalone translate key opening
    /// the session itself, starts directly in `.translate`.
    case start(suppress: Bool, mode: DictationMode)
    case stop(suppress: Bool, mode: DictationMode)
    /// The additional translate key latched translate LIVE, mid-hold, on an event
    /// that otherwise passes through. Surfaced so the UI can switch the recording
    /// glyph the moment the latch engages instead of waiting for the stop edge.
    /// Fires at most once per session (the latch is one-way); the underlying event
    /// is passed through.
    case translateLatched
    /// A non-trigger key went down while a passthrough-modifier trigger was held: cancel
    /// the in-flight dictation silently; the real combo passes through untouched.
    case interruptCancel
    /// The tap was disabled; re-enable it. `synthesizedStop` carries the mode of the
    /// session believed open, so a stuck "down" is released in the very mode the
    /// recording glyph is already showing; `nil` when nothing was held.
    case resync(synthesizedStop: DictationMode?)
    /// Nothing to do; pass the event through unchanged.
    case passThrough
}

/// The tap-free push-to-talk decision core. Maps each reduced input event to a
/// `HotkeyDecision` by composing a recognizer for the push-to-talk key, the
/// configured translate key in its role, and the session policy that turns their
/// answers into decisions — so the CGEventTap adapter stays a thin translator with
/// no policy of its own. It reads no clock and performs no I/O; every piece of its
/// state is updated deterministically on every path.
public struct HotkeyDecisionCore {
    /// What the configured translate key does. Exactly one role is live, so a key
    /// that both latches onto a hold and opens holds of its own is unrepresentable.
    private enum TranslateRole {
        /// Additional: pressed at any moment of a push-to-talk hold, it turns that
        /// one dictation into a translation. It opens no hold, so with nothing held
        /// its events are none of the decision's business and pass through.
        case latch(TriggerRecognizer)
        /// Standalone: a second push-to-talk key, whose every hold translates from
        /// the key-down edge. Nothing latches while the translate key stands alone.
        case source(TriggerRecognizer)

        init(_ configuration: HotkeyConfiguration) {
            let key = TriggerRecognizer(trigger: configuration.translate)
            self = configuration.translateIsAdditional ? .latch(key) : .source(key)
        }
    }

    /// One push-to-talk hold. Its mode lives INSIDE it, so a latched intent without
    /// a hold is unrepresentable: an abnormal end (interrupt-cancel, tap death)
    /// takes the intent with it.
    private struct Session {
        /// The key that opened this hold. It alone judges the release, says whether
        /// the events are suppressed and whether a combo may interrupt, and carries
        /// fn's engage key code across the hold.
        var key: TriggerRecognizer
        /// What this hold stops in: `.translate` from the key-down edge for a
        /// standalone translate hold or with the additional key already held, and
        /// one-way from `.plain` the moment the additional key latches mid-hold.
        var mode: DictationMode
    }

    /// Whether a push-to-talk hold is open.
    public var isTriggerHeld: Bool { session != nil }

    private let pushToTalkKey: TriggerRecognizer
    private let translateKey: TranslateRole
    private var session: Session?

    public init(configuration: HotkeyConfiguration) {
        pushToTalkKey = TriggerRecognizer(trigger: configuration.main)
        translateKey = TranslateRole(configuration)
    }

    /// Applies a live key change. A reconfigured core is a FRESH core: both roles
    /// are rebuilt from the new configuration and any open hold is dropped, so no
    /// state judged against the old keys can survive.
    public mutating func reconfigure(to configuration: HotkeyConfiguration) {
        self = HotkeyDecisionCore(configuration: configuration)
    }

    public mutating func handle(_ event: HotkeyInputEvent) -> HotkeyDecision {
        switch event {
        case let .flagsChanged(keyCode, flags):
            return handleFlagsChanged(keyCode: keyCode, flags: flags)
        case .keyDown:
            // A key press while an interruptible hold is open = the user reaching for
            // a shortcut, not dictating: cancel silently, the combo passes through.
            guard let hold = session, hold.key.isInterruptible else { return .passThrough }
            session = nil
            return .interruptCancel
        case .tapDisabled:
            // The emergency stop keeps the hold's mode: the recording glyph has been
            // showing it, so an abnormal end must not silently downgrade it.
            let synthesizedStop = session?.mode
            session = nil
            return .resync(synthesizedStop: synthesizedStop)
        }
    }

    private mutating func handleFlagsChanged(keyCode: Int64, flags: HotkeyModifierFlags) -> HotkeyDecision {
        guard let hold = session else { return openHold(keyCode: keyCode, flags: flags) }
        // The latch is read BEFORE the hold's own key judges the event, so a foreign
        // latch key latches even on an event that is not the hold key's; it is
        // one-way, so only a still-plain hold can change.
        let latchesNow = hold.mode == .plain && translateLatchEngages(keyCode: keyCode, flags: flags)
        let mode: DictationMode = latchesNow ? .translate : hold.mode
        session?.mode = mode
        guard hold.key.releases(keyCode: keyCode, flags: flags) else {
            // A fresh latch only ever coincides with an event that passes through (the
            // hold key is still down, so this is neither a start nor a stop); surface
            // it live so the recording glyph switches without waiting for the stop.
            return latchesNow ? .translateLatched : .passThrough
        }
        session = nil
        return .stop(suppress: hold.key.suppressesEvent, mode: mode)
    }

    private mutating func openHold(keyCode: Int64, flags: HotkeyModifierFlags) -> HotkeyDecision {
        guard var opening = openingHold(keyCode: keyCode, flags: flags) else { return .passThrough }
        opening.key.recordEngage(keyCode: keyCode)
        session = opening
        return .start(suppress: opening.key.suppressesEvent, mode: opening.mode)
    }

    /// The hold this event opens, if any. The push-to-talk key is consulted FIRST,
    /// so a configuration naming one key in both roles — which loading validation
    /// rejects — degenerates to the main key alone instead of racing.
    private func openingHold(keyCode: Int64, flags: HotkeyModifierFlags) -> Session? {
        if pushToTalkKey.engages(keyCode: keyCode, flags: flags) {
            // An additional translate key already held at key-down counts, so the
            // start itself carries `.translate` and the glyph never flashes plain.
            let isLatched = translateLatchEngages(keyCode: keyCode, flags: flags)
            return Session(key: pushToTalkKey, mode: isLatched ? .translate : .plain)
        }
        guard case let .source(key) = translateKey, key.engages(keyCode: keyCode, flags: flags) else { return nil }
        return Session(key: key, mode: .translate)
    }

    /// Whether this event presses the key that latches translate onto an open hold.
    /// Never true while the translate key stands alone: it opens its own holds and
    /// latches nothing.
    private func translateLatchEngages(keyCode: Int64, flags: HotkeyModifierFlags) -> Bool {
        guard case let .latch(key) = translateKey else { return false }
        return key.engages(keyCode: keyCode, flags: flags)
    }
}
