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
/// `HotkeyDecision` and owns the "trigger currently held" bit, so the CGEventTap
/// adapter stays a thin translator with no policy of its own. It reads no clock
/// and performs no I/O; every piece of its state is updated deterministically on
/// every path.
public struct HotkeyDecisionCore {
    public private(set) var isTriggerHeld = false
    private var trigger: HotkeyTrigger
    /// Latches translate intent for the current session: any Control during the
    /// hold latches, so the stop carries `.translate`. Full lifecycle, so a reader need
    /// not reconstruct it from the scattered mutation sites:
    /// - reset at each session START edge, so a stale latch never carries over;
    /// - observed on every held `flagsChanged` before the key-code passthrough guard
    ///   (a non-trigger Control still latches) and on the start event itself (Control
    ///   already held at key-down counts);
    /// - consumed at the STOP edge to pick `.translate` over `.plain`.
    /// A value left by an abnormal end (`.keyDown` interrupt-cancel or `.tapDisabled`,
    /// which do not clear it) is harmless: the next start's reset discards it first.
    private var isControlLatched = false
    /// The canonical fn virtual key code. An fn-bit-free event carrying it always
    /// ends the session, so even a session that started on a junk code can be
    /// released by the real key — no stuck hot mic.
    fileprivate static let fnKeyCode: Int64 = 63
    /// The key code the current fn session started on, latched at the engage edge.
    /// External keyboards report fn under their own codes (see
    /// docs/references/macos-fn-hotkey.md), so the start code is the only proof that
    /// a later fn-bit-free event is THIS key going up rather than unrelated noise.
    /// Read only while a session is held, and re-latched at every start edge, so a
    /// value left behind by a stop or an abnormal end can never be read; the
    /// `reconfigure` reset is belt-and-suspenders after a live trigger change.
    private var fnSessionStartKeyCode: Int64 = HotkeyDecisionCore.fnKeyCode

    public init(trigger: HotkeyTrigger) {
        self.trigger = trigger
    }

    /// Applies a live trigger change, resetting the held bit so the next event is
    /// judged against a clean state.
    public mutating func reconfigure(to trigger: HotkeyTrigger) {
        self.trigger = trigger
        isTriggerHeld = false
        isControlLatched = false
        fnSessionStartKeyCode = Self.fnKeyCode
    }

    public mutating func handle(_ event: HotkeyInputEvent) -> HotkeyDecision {
        switch event {
        case let .flagsChanged(keyCode, flags):
            return handleFlagsChanged(keyCode: keyCode, flags: flags)
        case .keyDown:
            // A key press while a passthrough-modifier trigger is held = the user
            // reaching for a shortcut, not dictating: cancel silently, combo
            // passes through. fn is suppressed and cannot form combos, so it has
            // no interrupt path.
            if isTriggerHeld, trigger.behavior == .passthroughModifier {
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
        // The start edge (and its own latch observation) lives in `edge`; only a
        // held session observes the latch here — before the key-code passthrough
        // guard below, so a non-trigger Control key still latches even though its
        // event passes through.
        guard isTriggerHeld else {
            return decisionForFlags(keyCode: keyCode, flags: flags)
        }
        let wasLatched = isControlLatched
        observeControlLatch(flags: flags)
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
            // The START edge stays keyed on the secondary-fn bit alone, key code
            // ignored, so an odd-code keyboard still begins a session.
            let engaged = flags.contains(.secondaryFn)
            if engaged, !isTriggerHeld { fnSessionStartKeyCode = keyCode }
            // Missing fn bit is NOT proof the key came up: macOS delivers junk and
            // foreign-modifier events without it while fn is still physically down.
            // Only an event naming the fn key ends the hold — this session's start
            // code, or the canonical one, which heals a junk-code start.
            if isTriggerHeld, !engaged, keyCode != fnSessionStartKeyCode, keyCode != Self.fnKeyCode {
                return .passThrough
            }
            return edge(engaged: engaged, suppress: true, flags: flags)
        case .passthroughModifier:
            // The flags carry the modifier class but not the side, so the key code
            // is what names the one key this trigger accepts; any other key is
            // not ours.
            guard keyCode == trigger.virtualKeyCode else { return .passThrough }
            // While the trigger is held, its own key code IS the release: the class
            // bit cannot say which side moved while both same-class keys are down,
            // and flagsChanged has no key repeat, so a physically-down key's next
            // own event can only be its way up. A START still demands the class bit,
            // so an idle release echo never opens a phantom session.
            let engaged = !isTriggerHeld && flags.contains(trigger.modifierFlag)
            return edge(engaged: engaged, suppress: false, flags: flags)
        }
    }

    /// Latches translate when Control engages during the hold. Control is never a
    /// trigger, so the class bit alone proves it — there is no side to disambiguate.
    /// One-way: once latched it stays latched until the session's start/stop resets.
    private mutating func observeControlLatch(flags: HotkeyModifierFlags) {
        guard !isControlLatched else { return }
        isControlLatched = flags.contains(.control)
    }

    private mutating func edge(engaged: Bool, suppress: Bool, flags: HotkeyModifierFlags) -> HotkeyDecision {
        if engaged, !isTriggerHeld {
            isTriggerHeld = true
            // Fresh session: clear any prior latch, then let Control-already-held at
            // key-down latch this session so the start already carries `.translate`.
            isControlLatched = false
            observeControlLatch(flags: flags)
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
    /// flag alone and suppressed, with no interrupt path; every other modifier is
    /// detected by key code, passes through, and can be interrupted by a combo.
    enum Behavior {
        case suppressedFn
        case passthroughModifier
    }

    var behavior: Behavior {
        self == .fn ? .suppressedFn : .passthroughModifier
    }

    /// The one virtual key code that counts as this trigger — a single physical key
    /// each, which is what lets a hold be told apart from the same modifier on the
    /// other side. fn is recognized by its modifier flag instead, so its code is
    /// informational.
    var virtualKeyCode: Int64 {
        switch self {
        case .fn: return HotkeyDecisionCore.fnKeyCode
        case .leftCommand: return 55
        case .rightCommand: return 54
        case .leftOption: return 58
        case .rightOption: return 61
        case .leftShift: return 56
        case .rightShift: return 60
        }
    }

    /// The modifier bit whose engage edge starts this trigger. Both sides of a pair
    /// share one bit — the flags name the class, never the side.
    var modifierFlag: HotkeyModifierFlags {
        switch self {
        case .fn: return .secondaryFn
        case .leftCommand, .rightCommand: return .command
        case .leftOption, .rightOption: return .option
        case .leftShift, .rightShift: return .shift
        }
    }
}
