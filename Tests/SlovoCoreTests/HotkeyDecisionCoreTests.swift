import Testing

import SlovoCore

// The tap-free push-to-talk decision core. Every edge the real CGEventTap must
// act on is decided here (the tap is a thin adapter), so these unit tests carry
// the trigger policy that hardware-only code cannot cover in CI.
@Suite("Hotkey decision core")
struct HotkeyDecisionCoreTests {

    /// fn: the secondary-fn flag edge starts and stops, and the event is
    /// suppressed (hidden from the OS) — exactly today's behavior.
    /// Stated sensitivity: drop fn suppression (return `.start(suppress: false)`)
    /// → RED; miss the flag edge → RED.
    @Test
    func fnFlagEdgeStartsAndStopsSuppressed() {
        var core = HotkeyDecisionCore(trigger: .fn)
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn])) == .start(suppress: true))
        #expect(core.isTriggerHeld)
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true))
        #expect(!core.isTriggerHeld)
    }

    /// fn has NO interrupt path: a key press while fn is held is passed through and
    /// fn stays held (fn is suppressed and cannot form combos).
    /// Stated sensitivity: give fn an interrupt path (return `.interruptCancel`) →
    /// RED.
    @Test
    func fnHasNoInterruptPath() {
        var core = HotkeyDecisionCore(trigger: .fn)
        _ = core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn]))
        #expect(core.handle(.keyDown) == .passThrough)
        #expect(core.isTriggerHeld, "fn must stay held; a keypress does not interrupt fn")
    }

    /// A right modifier starts/stops on its side-specific key code + modifier bit,
    /// and is NOT suppressed (it keeps working as a normal modifier system-wide).
    /// Stated sensitivity: suppress a right modifier (`.start(suppress: true)`) →
    /// RED. This is ALSO the test that catches the trigger-table key-code flip
    /// (Right ⌘ 54 → Right ⌥ 61): under that mutation key code 54 no longer matches
    /// the trigger, so the expected `.start` becomes `.passThrough` → RED.
    @Test
    func rightModifierStartsAndStopsPassedThrough() {
        var core = HotkeyDecisionCore(trigger: .rightCommand)
        #expect(core.handle(.flagsChanged(keyCode: 54, flags: [.command])) == .start(suppress: false))
        #expect(core.isTriggerHeld)
        #expect(core.handle(.flagsChanged(keyCode: 54, flags: [])) == .stop(suppress: false))
        #expect(!core.isTriggerHeld)
    }

    /// A non-trigger key going down while a right modifier is held cancels the
    /// in-flight dictation; the real combo passes through untouched.
    /// Stated sensitivity: remove the interrupt branch → RED (no cancel emitted).
    @Test
    func rightModifierComboInterruptsWithCancel() {
        var core = HotkeyDecisionCore(trigger: .rightCommand)
        _ = core.handle(.flagsChanged(keyCode: 54, flags: [.command]))
        #expect(core.handle(.keyDown) == .interruptCancel)
        #expect(!core.isTriggerHeld, "an interrupt releases the held trigger")
    }

    /// The wrong side of the same modifier class is not this trigger: LEFT command
    /// (key code 55) must not start a Right ⌘ trigger.
    /// Stated sensitivity: match on the modifier bit alone (ignore the key code) →
    /// left command starts dictation → RED.
    @Test
    func wrongSideModifierDoesNotStart() {
        var core = HotkeyDecisionCore(trigger: .rightCommand)
        #expect(core.handle(.flagsChanged(keyCode: 55, flags: [.command])) == .passThrough)
        #expect(!core.isTriggerHeld)
    }

    /// A non-matching key code must not start, even when the trigger's OWN modifier
    /// bit is present: with Right ⌘ selected, an event carrying the command bit but
    /// the Right ⌥ key code (61) is not this trigger. The probe deliberately pairs
    /// the command bit (trigger's modifier) with the wrong key code so the key-code
    /// guard is the ONLY thing keeping it from starting.
    /// Stated sensitivity: drop or ignore the key-code guard (match on the modifier
    /// bit alone) → `edge(engaged: true)` → `.start` → RED. (It also reddens on the
    /// 54→61 table flip, which makes key code 61 match the trigger.)
    @Test
    func differentRightModifierKeyCodeDoesNotStart() {
        var core = HotkeyDecisionCore(trigger: .rightCommand)
        #expect(core.handle(.flagsChanged(keyCode: 61, flags: [.command])) == .passThrough)
        #expect(!core.isTriggerHeld)
    }

    /// Tap death while a trigger is held resyncs by synthesizing an up, so
    /// push-to-talk can never stick "down" after the tap is re-enabled.
    /// Stated sensitivity: drop the synthesized up (return `.resync(synthesizeUp:
    /// false)` when held) → the held trigger is not released → RED.
    @Test
    func tapDeathWhileHeldSynthesizesUp() {
        var core = HotkeyDecisionCore(trigger: .rightControl)
        _ = core.handle(.flagsChanged(keyCode: 62, flags: [.control]))
        #expect(core.handle(.tapDisabled) == .resync(synthesizeUp: true))
        #expect(!core.isTriggerHeld)
    }

    /// Tap death with nothing held resyncs without a synthetic up.
    /// Stated sensitivity: always synthesize an up → a spurious stop is emitted
    /// when idle → RED.
    @Test
    func tapDeathWhileIdleDoesNotSynthesizeUp() {
        var core = HotkeyDecisionCore(trigger: .fn)
        #expect(core.handle(.tapDisabled) == .resync(synthesizeUp: false))
    }

    /// Reconfiguring to a new trigger resets the held state, so a live key change
    /// starts clean.
    /// Stated sensitivity: keep the held bit across reconfigure → the next event is
    /// judged against stale held state → RED.
    @Test
    func reconfigureResetsHeldState() {
        var core = HotkeyDecisionCore(trigger: .rightCommand)
        _ = core.handle(.flagsChanged(keyCode: 54, flags: [.command]))
        core.reconfigure(to: .rightShift)
        #expect(!core.isTriggerHeld)
        #expect(core.handle(.flagsChanged(keyCode: 60, flags: [.shift])) == .start(suppress: false))
    }
}
