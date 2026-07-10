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
    case start(suppress: Bool)
    case stop(suppress: Bool)
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

    public init(trigger: HotkeyTrigger) {
        self.trigger = trigger
    }

    /// Applies a live trigger change, resetting the held bit so the next event is
    /// judged against a clean state.
    public mutating func reconfigure(to trigger: HotkeyTrigger) {
        self.trigger = trigger
        isTriggerHeld = false
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
            return .resync(synthesizeUp: wasHeld)
        }
    }

    private mutating func handleFlagsChanged(keyCode: Int64, flags: HotkeyModifierFlags) -> HotkeyDecision {
        switch trigger.behavior {
        case .suppressedFn:
            // fn is keyed on the secondary-fn bit edge, key code ignored — exactly
            // the pre-existing detection.
            return edge(engaged: flags.contains(.secondaryFn), suppress: true)
        case .passthroughRightModifier:
            // The flags carry the modifier class but not the side, so a right
            // modifier requires its side-specific key code; the same class on the
            // other side (or a different key) is not ours.
            guard keyCode == trigger.virtualKeyCode else { return .passThrough }
            return edge(engaged: flags.contains(trigger.modifierFlag), suppress: false)
        }
    }

    private mutating func edge(engaged: Bool, suppress: Bool) -> HotkeyDecision {
        if engaged, !isTriggerHeld {
            isTriggerHeld = true
            return .start(suppress: suppress)
        }
        if !engaged, isTriggerHeld {
            isTriggerHeld = false
            return .stop(suppress: suppress)
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
