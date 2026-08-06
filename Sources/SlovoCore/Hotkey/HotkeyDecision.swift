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
            switch configuration.translateGesture {
            case .additional: self = .latch(key)
            case .standalone: self = .source(key)
            }
        }
    }

    /// What the core knows about the key that is physically down.
    private enum Hold {
        /// A live dictation.
        case dictating(Session)
        /// A dictation cancelled mid-hold. Its key is still down, so it keeps owning
        /// the core until it comes up: nothing may start meanwhile. Without this, a
        /// class-detected key — recognized by its modifier bit alone, on any key code
        /// — re-engages on the very next modifier event of the shortcut the user was
        /// reaching for, and records and inserts a dictation nobody asked for.
        case cancelled(TriggerRecognizer)
    }

    /// One live dictation. Its mode lives INSIDE it, so a latched intent without a
    /// dictation is unrepresentable: an abnormal end (interrupt-cancel, tap death)
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

    /// Whether a dictation is live.
    public var isTriggerHeld: Bool { dictation != nil }

    private let pushToTalkKey: TriggerRecognizer
    private let translateKey: TranslateRole
    private var hold: Hold?

    /// The live dictation, if the key that is down is still driving one.
    private var dictation: Session? {
        guard case let .dictating(session) = hold else { return nil }
        return session
    }

    public init(configuration: HotkeyConfiguration) {
        pushToTalkKey = TriggerRecognizer(trigger: configuration.main)
        translateKey = TranslateRole(configuration)
    }

    /// Applies a live key change. A reconfigured core is a FRESH core: both roles are
    /// rebuilt from the new configuration and any hold is dropped, live or cancelled,
    /// so no state judged against the old keys can survive.
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
            guard let session = dictation, session.key.isInterruptible else { return .passThrough }
            // The key is still down and the shortcut it belongs to is still being
            // typed, so the hold survives as cancelled rather than disappearing.
            hold = .cancelled(session.key)
            return .interruptCancel
        case .tapDisabled:
            // The emergency stop keeps the hold's mode: the recording glyph has been
            // showing it, so an abnormal end must not silently downgrade it. Nothing
            // is disarmed here: the blackout swallowed events, so which key is still
            // down is a guess — and fn's release, the least reliably detected of the
            // three, may already be among the swallowed ones, stranding the core.
            let synthesizedStop = dictation?.mode
            hold = nil
            return .resync(synthesizedStop: synthesizedStop)
        }
    }

    private mutating func handleFlagsChanged(keyCode: Int64, flags: HotkeyModifierFlags) -> HotkeyDecision {
        switch hold {
        case .none:
            return openHold(keyCode: keyCode, flags: flags)
        case let .cancelled(key):
            // Only this key coming up re-arms the core; every other event of the
            // shortcut in progress is none of its business.
            if key.releases(keyCode: keyCode, flags: flags) { hold = nil }
            return .passThrough
        case let .dictating(session):
            // The latch is read BEFORE the hold's own key judges the event, so a
            // foreign latch key latches even on an event that is not the hold key's;
            // it is one-way, so only a still-plain hold can change.
            let latchesNow = session.mode == .plain && translateLatchEngages(keyCode: keyCode, flags: flags)
            let mode: DictationMode = latchesNow ? .translate : session.mode
            guard session.key.releases(keyCode: keyCode, flags: flags) else {
                hold = .dictating(Session(key: session.key, mode: mode))
                // A fresh latch only ever coincides with an event that passes through
                // (the hold key is still down, so this is neither a start nor a stop);
                // surface it live so the glyph switches without waiting for the stop.
                return latchesNow ? .translateLatched : .passThrough
            }
            hold = nil
            return .stop(suppress: session.key.suppressesEvent, mode: mode)
        }
    }

    private mutating func openHold(keyCode: Int64, flags: HotkeyModifierFlags) -> HotkeyDecision {
        guard var opening = openingHold(keyCode: keyCode, flags: flags) else { return .passThrough }
        opening.key.recordEngage(keyCode: keyCode)
        hold = .dictating(opening)
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
