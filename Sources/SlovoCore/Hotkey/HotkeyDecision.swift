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
/// for fn (its event is hidden from the OS); a right modifier passes through so it
/// keeps working as a normal modifier.
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
    /// A non-trigger key went down while a right-modifier trigger was held: cancel
    /// the in-flight dictation silently; the real combo passes through untouched.
    case interruptCancel
    /// The tap was disabled; re-enable it. `synthesizeUp` is true when a trigger
    /// was believed held, so a stuck "down" is released.
    case resync(synthesizeUp: Bool)
    /// Nothing to do; pass the event through unchanged.
    case passThrough
}

/// The tap-free push-to-talk decision core. Maps each reduced input event to a
/// `HotkeyDecision` and owns the "trigger currently held" bit, so the CGEventTap
/// adapter stays a thin translator with no policy of its own. It reads no clock
/// and performs no I/O; its only state is the held bit, updated deterministically
/// on every path.
public struct HotkeyDecisionCore {
    public private(set) var isTriggerHeld = false
    private var trigger: HotkeyTrigger
    /// Latches translate intent for the current session: while held, ANY Control
    /// latches, so the stop carries `.translate`. Full lifecycle, so a reader need
    /// not reconstruct it from the scattered mutation sites:
    /// - reset at each session START edge, so a stale latch never carries over;
    /// - observed on every held `flagsChanged` before the key-code passthrough guard
    ///   (a non-trigger Control still latches) and on the start event itself (Control
    ///   already held at key-down counts);
    /// - consumed at the STOP edge to pick `.translate` over `.plain`.
    /// A value left by an abnormal end (`.keyDown` interrupt-cancel or `.tapDisabled`,
    /// which do not clear it) is harmless: the next start's reset discards it first.
    private var isControlLatched = false
    /// The LEFT Control key code, distinct from the Right ⌃ trigger's own key code
    /// (62): a Right ⌃ hold must not self-latch, but a SECOND, foreign Control still
    /// latches translate. The flags carry a single `.control` bit either way, so
    /// only the key code tells the two apart.
    private static let leftControlKeyCode: Int64 = 59
    /// Whether the LEFT Control key is physically down, tracked on EVERY
    /// `flagsChanged` (session or not). The Right ⌃ start event carries the
    /// trigger's own key code and the sideless `.control` class bit, so only this
    /// bit lets a Control pre-held BEFORE key-down latch translate at the start
    /// edge. Reset on `reconfigure` and `.tapDisabled` — after a config change or
    /// a tap gap the bit may be stale, and a conservative drop can only miss a
    /// latch, never invent one.
    private var isLeftControlDown = false

    public init(trigger: HotkeyTrigger) {
        self.trigger = trigger
    }

    /// Applies a live trigger change, resetting the held bit so the next event is
    /// judged against a clean state.
    public mutating func reconfigure(to trigger: HotkeyTrigger) {
        self.trigger = trigger
        isTriggerHeld = false
        isControlLatched = false
        isLeftControlDown = false
    }

    public mutating func handle(_ event: HotkeyInputEvent) -> HotkeyDecision {
        switch event {
        case let .flagsChanged(keyCode, flags):
            return handleFlagsChanged(keyCode: keyCode, flags: flags)
        case .keyDown:
            // A key press while a right-modifier trigger is held = the user
            // reaching for a shortcut, not dictating: cancel silently, combo
            // passes through. fn is suppressed and cannot form combos, so it has
            // no interrupt path.
            if isTriggerHeld, trigger.behavior == .passthroughRightModifier {
                isTriggerHeld = false
                return .interruptCancel
            }
            return .passThrough
        case .tapDisabled:
            let wasHeld = isTriggerHeld
            isTriggerHeld = false
            isLeftControlDown = false
            return .resync(synthesizeUp: wasHeld)
        }
    }

    private mutating func handleFlagsChanged(keyCode: Int64, flags: HotkeyModifierFlags) -> HotkeyDecision {
        // Must run before any latch decision below reads the bit for this event.
        trackLeftControl(keyCode: keyCode, flags: flags)
        // The start edge (and its own latch observation) lives in `edge`; only a
        // held session observes the latch here — before the key-code passthrough
        // guard below, so a non-trigger Control key still latches even though its
        // event passes through.
        guard isTriggerHeld else {
            return decisionForFlags(keyCode: keyCode, flags: flags)
        }
        let wasLatched = isControlLatched
        observeControlLatch(keyCode: keyCode, flags: flags)
        let decision = decisionForFlags(keyCode: keyCode, flags: flags)
        // A fresh mid-hold latch only ever coincides with a passthrough event (the
        // trigger bit is still engaged, so this is neither a start nor a stop);
        // surface it live so the recording glyph can switch without waiting for stop.
        if !wasLatched, isControlLatched, decision == .passThrough {
            return .translateLatched
        }
        return decision
    }

    private mutating func decisionForFlags(keyCode: Int64, flags: HotkeyModifierFlags) -> HotkeyDecision {
        switch trigger.behavior {
        case .suppressedFn:
            // fn is keyed on the secondary-fn bit edge, key code ignored — exactly
            // the pre-existing detection.
            return edge(engaged: flags.contains(.secondaryFn), suppress: true, keyCode: keyCode, flags: flags)
        case .passthroughRightModifier:
            // The flags carry the modifier class but not the side, so a right
            // modifier requires its side-specific key code; the same class on the
            // other side (or a different key) is not ours.
            guard keyCode == trigger.virtualKeyCode else { return .passThrough }
            return edge(engaged: flags.contains(trigger.modifierFlag), suppress: false, keyCode: keyCode, flags: flags)
        }
    }

    /// Latches translate when Control engages during the hold. A Right ⌃ trigger
    /// must not self-latch, so when the trigger IS Control only the LEFT (second)
    /// Control latches — either this very event is the kc59 key, or the tracked
    /// bit says left Control was already down when the start edge fired (the start
    /// event's own key code is the trigger's, so the bit is the only carrier
    /// there). For every other trigger the `.control` bit suffices.
    /// One-way: once latched it stays latched until the session's start/stop resets.
    private mutating func observeControlLatch(keyCode: Int64, flags: HotkeyModifierFlags) {
        guard !isControlLatched else { return }
        if trigger.modifierFlag == .control {
            isControlLatched = keyCode == Self.leftControlKeyCode || isLeftControlDown
        } else {
            isControlLatched = flags.contains(.control)
        }
    }

    /// Keeps `isLeftControlDown` current from the raw event stream. A kc59 event
    /// follows the `.control` class bit (its release still carries the bit while
    /// the right side holds it — a brief stale-true window); any control-free
    /// event proves BOTH sides are up and heals the bit, and the trigger's own
    /// control-free release edge always precedes the next start, so a stale bit
    /// can never reach a start-edge latch.
    private mutating func trackLeftControl(keyCode: Int64, flags: HotkeyModifierFlags) {
        if keyCode == Self.leftControlKeyCode {
            isLeftControlDown = flags.contains(.control)
        } else if !flags.contains(.control) {
            isLeftControlDown = false
        }
    }

    private mutating func edge(engaged: Bool, suppress: Bool, keyCode: Int64, flags: HotkeyModifierFlags) -> HotkeyDecision {
        if engaged, !isTriggerHeld {
            isTriggerHeld = true
            // Fresh session: clear any prior latch, then let Control-already-held at
            // key-down latch this session so the start already carries `.translate`.
            isControlLatched = false
            observeControlLatch(keyCode: keyCode, flags: flags)
            return .start(suppress: suppress, mode: isControlLatched ? .translate : .plain)
        }
        if !engaged, isTriggerHeld {
            isTriggerHeld = false
            let mode: DictationMode = isControlLatched ? .translate : .plain
            isControlLatched = false
            return .stop(suppress: suppress, mode: mode)
        }
        return .passThrough
    }
}

extension HotkeyTrigger {
    /// How the tap recognizes and treats a trigger: fn is detected by its modifier
    /// flag alone and suppressed, with no interrupt path; a right-hand modifier is
    /// detected by its side-specific key code, passes through, and can be
    /// interrupted by a combo.
    enum Behavior {
        case suppressedFn
        case passthroughRightModifier
    }

    var behavior: Behavior {
        self == .fn ? .suppressedFn : .passthroughRightModifier
    }

    /// The side-specific virtual key code the tap matches for a right-hand
    /// modifier. fn is recognized by its modifier flag instead, so its key code is
    /// informational only.
    var virtualKeyCode: Int64 {
        switch self {
        case .fn: return 63
        case .rightCommand: return 54
        case .rightOption: return 61
        case .rightControl: return 62
        case .rightShift: return 60
        }
    }

    /// The modifier bit whose engage/release edge drives this trigger.
    var modifierFlag: HotkeyModifierFlags {
        switch self {
        case .fn: return .secondaryFn
        case .rightCommand: return .command
        case .rightOption: return .option
        case .rightControl: return .control
        case .rightShift: return .shift
        }
    }
}
