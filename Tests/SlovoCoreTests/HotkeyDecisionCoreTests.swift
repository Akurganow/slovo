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
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn])) == .start(suppress: true, mode: .plain))
        #expect(core.isTriggerHeld)
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .plain))
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
        #expect(core.handle(.flagsChanged(keyCode: 54, flags: [.command])) == .start(suppress: false, mode: .plain))
        #expect(core.isTriggerHeld)
        #expect(core.handle(.flagsChanged(keyCode: 54, flags: [])) == .stop(suppress: false, mode: .plain))
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
        #expect(core.handle(.flagsChanged(keyCode: 60, flags: [.shift])) == .start(suppress: false, mode: .plain))
    }

    // MARK: - Control-latch: holding Control at any moment during the hold latches
    // the session's stop into `.translate` (default is `.plain`).

    /// Plain-path baseline: a hold with NO control at any point stops in `.plain`.
    /// Stated sensitivity: default the latch to `.translate` (or latch when control
    /// is absent) → this stop reads `.translate` → RED.
    @Test
    func heldWithoutControlStaysPlain() {
        var core = HotkeyDecisionCore(trigger: .fn)
        _ = core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn]))
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .plain))
    }

    /// L2 — Control pressed MID-hold latches translate: fn down, then a control key
    /// goes down while fn is still held, then fn up ⇒ `.stop(mode: .translate)`.
    /// RED now (the baseline always emits `.plain`).
    /// Stated sensitivity: never observe control during the hold → the stop stays
    /// `.plain` → RED.
    @Test
    func controlPressedMidHoldLatchesTranslate() {
        var core = HotkeyDecisionCore(trigger: .fn)
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn])) == .start(suppress: true, mode: .plain))
        // A control key engages while fn is still held (fn bit still present).
        _ = core.handle(.flagsChanged(keyCode: 59, flags: [.secondaryFn, .control]))
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .translate))
    }

    /// L3 — Control ALREADY held at key-down latches translate for every non-control
    /// trigger, even when Control is released BEFORE key-up. Passes on the correct
    /// code. The release event deliberately carries NO `.control` (Control let go
    /// before the trigger), so the key-down START edge is the ONLY latch opportunity:
    /// a stop still carrying `.control` would re-latch at the stop edge and mask the
    /// mutation below.
    /// Stated sensitivity: remove the start-edge observe (the `observeControlLatch`
    /// in the start branch of `edge`) → nothing latches this session → the
    /// control-free release stops `.plain` → RED.
    @Test
    func controlHeldAtKeyDownLatchesTranslate() {
        // (trigger, side-specific key code, the trigger's own modifier bit)
        let cases: [(HotkeyTrigger, Int64, HotkeyModifierFlags)] = [
            (.fn, 63, .secondaryFn),
            (.rightCommand, 54, .command),
            (.rightOption, 61, .option),
            (.rightShift, 60, .shift),
        ]
        for (trigger, keyCode, flag) in cases {
            var core = HotkeyDecisionCore(trigger: trigger)
            let suppress = trigger == .fn
            #expect(core.handle(.flagsChanged(keyCode: keyCode, flags: [flag, .control])) == .start(suppress: suppress, mode: .translate),
                    "\(trigger) must still start (in .translate) when control is already held at key-down")
            // Control already released before key-up: only the start edge could have latched.
            #expect(core.handle(.flagsChanged(keyCode: keyCode, flags: [])) == .stop(suppress: suppress, mode: .translate),
                    "\(trigger): control held at key-down must latch the session's stop into .translate")
        }
    }

    /// L4 — guard ordering: with a right-modifier trigger, a NON-trigger control key
    /// (left control, key code 59) engages mid-hold. That event returns passThrough
    /// at the `keyCode == trigger` guard, so the latch must be observed BEFORE that
    /// guard. Passes on the correct code. The trigger-release event drops `.control`
    /// so this test alone isolates the ordering: a release still carrying `.control`
    /// would re-latch at the stop edge and mask the mutation.
    /// Stated sensitivity: move the latch observe to AFTER the key-code passthrough
    /// guard → the kc59 event returns before latching, and the control-free release
    /// never latches → the stop stays `.plain` → RED.
    @Test
    func controlLatchIsObservedBeforeTheKeyCodePassthroughGuard() {
        var core = HotkeyDecisionCore(trigger: .rightCommand)
        #expect(core.handle(.flagsChanged(keyCode: 54, flags: [.command])) == .start(suppress: false, mode: .plain))
        // Left control (non-trigger key code) engages while Right ⌘ is held.
        _ = core.handle(.flagsChanged(keyCode: 59, flags: [.command, .control]))
        // Release the trigger with Control already gone: no stop-edge re-latch.
        #expect(core.handle(.flagsChanged(keyCode: 54, flags: [])) == .stop(suppress: false, mode: .translate))
    }

    /// L5(a) — the Right ⌃ trigger's OWN control must NOT self-latch: holding only
    /// right control and releasing it stops in `.plain`.
    /// Green now. Stated sensitivity: latch via `flags.contains(.control)` for this
    /// trigger, or latch on the trigger's own key code 62 → the plain hold self-
    /// latches into `.translate` → RED.
    @Test
    func rightControlTriggerDoesNotSelfLatch() {
        var core = HotkeyDecisionCore(trigger: .rightControl)
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [.control])) == .start(suppress: false, mode: .plain))
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [])) == .stop(suppress: false, mode: .plain))
    }

    /// L5(b) — a SECOND, foreign control (left control, key code 59) while the Right
    /// ⌃ trigger is held DOES latch translate. The flags carry a single `.control`
    /// bit either way, so only the foreign key code distinguishes it. RED now.
    /// Stated sensitivity: fail to latch on the foreign kc59 control → the stop stays
    /// `.plain` → RED.
    @Test
    func rightControlTriggerLatchesOnAForeignControl() {
        var core = HotkeyDecisionCore(trigger: .rightControl)
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [.control])) == .start(suppress: false, mode: .plain))
        _ = core.handle(.flagsChanged(keyCode: 59, flags: [.control]))
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [])) == .stop(suppress: false, mode: .translate))
    }

    /// L6 — the latch is per-session across a NORMAL stop→start: a translate-latched
    /// hold does not bleed into the next hold. Session A (with control) latches
    /// translate; session B (no control) on the SAME core stops `.plain`. Passes on
    /// the correct code.
    /// Stated sensitivity: the session-B `.plain` result is guarded by the STOP-edge
    /// reset (the normal stop clears `isControlLatched`), not the start-edge reset —
    /// drop the stop-edge reset and session B stays sticky `.translate` → RED. The
    /// start-edge reset (which only matters when a hold ends abnormally, with no stop)
    /// is owned by the F2 abnormal-exit tests below.
    @Test
    func controlLatchResetsPerSession() {
        var core = HotkeyDecisionCore(trigger: .fn)

        // Session A: control mid-hold latches translate.
        _ = core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn]))
        _ = core.handle(.flagsChanged(keyCode: 59, flags: [.secondaryFn, .control]))
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .translate))

        // Session B: no control at all → plain.
        _ = core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn]))
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .plain))
    }

    /// L7 — reconfiguring the trigger clears any latched translate, so a fresh plain
    /// session on the new trigger stops `.plain`. The pre-reconfigure latch assert is
    /// RED now.
    /// Stated sensitivity: keep the latch across `reconfigure` → the post-reconfigure
    /// plain session stops `.translate` → the second assert reddens.
    @Test
    func reconfigureClearsTheLatch() {
        var core = HotkeyDecisionCore(trigger: .fn)

        // Latch translate on fn.
        _ = core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn]))
        _ = core.handle(.flagsChanged(keyCode: 59, flags: [.secondaryFn, .control]))
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .translate))

        core.reconfigure(to: .rightShift)

        // A plain session on the new trigger (no control) must stay plain.
        _ = core.handle(.flagsChanged(keyCode: 60, flags: [.shift]))
        #expect(core.handle(.flagsChanged(keyCode: 60, flags: [])) == .stop(suppress: false, mode: .plain))
    }

    /// L8(a) — a left Control held since BEFORE the session latches the Right ⌃
    /// start edge into `.translate`. The start event's own key code is the
    /// trigger's (62) and the single `.control` class bit cannot name the side, so
    /// only a bit tracked from the earlier kc59 press can carry the knowledge to
    /// the start edge. RED now: the pre-session kc59 press is discarded
    /// (`isTriggerHeld` is false) and the start-edge latch sees only kc62 → the
    /// session starts and stops `.plain`.
    /// Stated sensitivity: drop the tracked-bit consult in the start-edge latch →
    /// the start reads `.plain` → RED.
    @Test
    func preHeldLeftControlLatchesRightControlStartEdge() {
        var core = HotkeyDecisionCore(trigger: .rightControl)
        // Left control goes down before any session; the event passes through.
        #expect(core.handle(.flagsChanged(keyCode: 59, flags: [.control])) == .passThrough)
        // The Right ⌃ trigger engages: the start must already carry .translate.
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [.control])) == .start(suppress: false, mode: .translate))
        // Left control released mid-hold (the class bit stays set — right holds it).
        _ = core.handle(.flagsChanged(keyCode: 59, flags: [.control]))
        // The session latch is one-way: the stop still carries .translate.
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [])) == .stop(suppress: false, mode: .translate))
    }

    /// L8(b) — a left Control pressed AND released before the session leaves no
    /// latch: the tracked bit must follow the release, not stick at the press.
    /// Green on the correct code (and trivially green pre-fix, where no bit exists).
    /// Stated sensitivity: make the tracked bit one-way (never cleared by the kc59
    /// release) → the start latches `.translate` → RED.
    @Test
    func leftControlReleasedBeforeSessionDoesNotLatch() {
        var core = HotkeyDecisionCore(trigger: .rightControl)
        _ = core.handle(.flagsChanged(keyCode: 59, flags: [.control]))
        _ = core.handle(.flagsChanged(keyCode: 59, flags: []))
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [.control])) == .start(suppress: false, mode: .plain))
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [])) == .stop(suppress: false, mode: .plain))
    }

    /// L8(c) — a STALE tracked bit heals before the next start edge can consume it.
    /// Releasing left Control while the trigger still holds the class bit leaves the
    /// bit stale-true (the kc59 release still carries `.control`, so the side is
    /// unprovable there); the trigger release carries no `.control` at all, which
    /// proves both sides are up and must clear the bit — session B stays `.plain`.
    /// Stated sensitivity: drop the control-free heal (update the bit on kc59 events
    /// only) → the stale bit latches session B's start into `.translate` → RED.
    @Test
    func staleLeftControlBitHealsOnControlFreeEventBeforeNextSession() {
        var core = HotkeyDecisionCore(trigger: .rightControl)
        // Session A: pre-held left control latches translate at the start edge.
        _ = core.handle(.flagsChanged(keyCode: 59, flags: [.control]))
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [.control])) == .start(suppress: false, mode: .translate))
        // Left up while the trigger is held: the class bit stays set (stale window).
        _ = core.handle(.flagsChanged(keyCode: 59, flags: [.control]))
        // The trigger release is control-free → heals the bit at the stop edge.
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [])) == .stop(suppress: false, mode: .translate))
        // Session B: no left control anywhere → must not latch from the stale bit.
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [.control])) == .start(suppress: false, mode: .plain))
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [])) == .stop(suppress: false, mode: .plain))
    }

    /// F2(a) — a latched hold that ends ABNORMALLY via `.tapDisabled` must not leave a
    /// sticky translate: the next fresh no-Control hold stops `.plain`. Passes on the
    /// correct code. The tap-death path emits no `.stop`, so the stop-edge reset never
    /// runs — ONLY the start-edge `isControlLatched = false` reset clears the leftover
    /// latch.
    /// Stated sensitivity: remove the start-edge latch reset → the leftover latch
    /// survives the tap death → the next session stops `.translate` → RED.
    @Test
    func latchDoesNotSurviveTapDisabledAbnormalExit() {
        var core = HotkeyDecisionCore(trigger: .fn)

        // Session 1: Control held at key-down latches translate...
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn, .control])) == .start(suppress: true, mode: .translate))
        // ...but the hold ends abnormally (tap death), emitting no stop.
        #expect(core.handle(.tapDisabled) == .resync(synthesizeUp: true))

        // Session 2: a fresh no-Control hold must stop plain.
        _ = core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn]))
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .plain))
    }

    /// F2(b) — a latched hold that ends ABNORMALLY via a `.keyDown` interrupt-cancel
    /// (right-modifier trigger, interrupt only fires for passthrough right modifiers)
    /// must not leave a sticky translate. Passes on the correct code. The interrupt
    /// path emits `.interruptCancel`, not `.stop`, so again only the start-edge reset
    /// clears the leftover latch.
    /// Stated sensitivity: remove the start-edge latch reset → the leftover latch
    /// survives the interrupt → the next session stops `.translate` → RED.
    @Test
    func latchDoesNotSurviveInterruptCancelAbnormalExit() {
        var core = HotkeyDecisionCore(trigger: .rightCommand)

        // Session 1: Control also held at key-down latches translate...
        #expect(core.handle(.flagsChanged(keyCode: 54, flags: [.command, .control])) == .start(suppress: false, mode: .translate))
        // ...but a non-trigger key goes down → interrupt-cancel (no stop).
        #expect(core.handle(.keyDown) == .interruptCancel)

        // Session 2: a fresh no-Control hold must stop plain.
        _ = core.handle(.flagsChanged(keyCode: 54, flags: [.command]))
        #expect(core.handle(.flagsChanged(keyCode: 54, flags: [])) == .stop(suppress: false, mode: .plain))
    }

    /// F3(a) — `reconfigure` drops the tracked left-Control bit: after a live
    /// trigger change the core deliberately distrusts every piece of pre-change
    /// state (same doctrine as the held-bit reset), so a left Control pressed
    /// before the change cannot latch the first session on the new trigger.
    /// Stated sensitivity: keep the bit across `reconfigure` → the post-change
    /// start latches `.translate` → RED.
    @Test
    func reconfigureClearsTheTrackedLeftControlBit() {
        var core = HotkeyDecisionCore(trigger: .fn)
        _ = core.handle(.flagsChanged(keyCode: 59, flags: [.control]))
        core.reconfigure(to: .rightControl)
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [.control])) == .start(suppress: false, mode: .plain))
    }

    /// F3(b) — `.tapDisabled` drops the tracked left-Control bit: a tap gap can
    /// swallow the kc59 release, so a bit carried across the gap may be stale —
    /// the conservative reset keeps a dead tap from latching a later session.
    /// Stated sensitivity: keep the bit across `.tapDisabled` → the post-resync
    /// start latches `.translate` → RED.
    @Test
    func tapDisabledClearsTheTrackedLeftControlBit() {
        var core = HotkeyDecisionCore(trigger: .rightControl)
        _ = core.handle(.flagsChanged(keyCode: 59, flags: [.control]))
        #expect(core.handle(.tapDisabled) == .resync(synthesizeUp: false))
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [.control])) == .start(suppress: false, mode: .plain))
    }

    /// F4(a) — a `.keyDown` interrupt-cancel must NOT clear the tracked
    /// left-Control bit: unlike a tap gap, the tap stays alive across an
    /// interrupt, so the bit is still trustworthy — a left Control held through
    /// the interrupt must latch the NEXT session's start edge into `.translate`.
    /// (From the core's view a kc62 + `.control` event while not held IS a start
    /// edge — the class bit cannot say whether the OTHER side made it a release —
    /// so the re-engage below is exactly what the tap delivers.)
    /// Stated sensitivity: clear the bit on the `.keyDown` interrupt → session
    /// B's start reads `.plain` → RED.
    @Test
    func interruptCancelKeepsTheTrackedLeftControlBit() {
        var core = HotkeyDecisionCore(trigger: .rightControl)
        _ = core.handle(.flagsChanged(keyCode: 59, flags: [.control]))
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [.control])) == .start(suppress: false, mode: .translate))
        // A non-trigger key press interrupts session A; the tap stays alive.
        #expect(core.handle(.keyDown) == .interruptCancel)
        // Left Control never left: the next engage must latch again from the bit.
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [.control])) == .start(suppress: false, mode: .translate))
    }

    /// F4(b) — the stale-window heal also covers the interrupt-cancel exit: left
    /// released mid-hold leaves the bit stale-true (the kc59 release still carries
    /// `.control` from the held trigger), the interrupt cancels with no stop edge,
    /// and the mandatory post-interrupt control-free trigger release heals the bit
    /// — session B stays `.plain`. Distinct from L8(c): there the healing event is
    /// session A's own STOP edge; here the session is already cancelled and the
    /// healing event is a non-held passthrough.
    /// Stated sensitivity: drop the control-free heal → the stale bit latches
    /// session B's start into `.translate` → RED (via the cancel path, with no
    /// stop edge anywhere before session B).
    @Test
    func staleLeftControlBitHealsAfterInterruptCancel() {
        var core = HotkeyDecisionCore(trigger: .rightControl)
        _ = core.handle(.flagsChanged(keyCode: 59, flags: [.control]))
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [.control])) == .start(suppress: false, mode: .translate))
        // Left up while the trigger is held: the class bit stays set (stale window).
        _ = core.handle(.flagsChanged(keyCode: 59, flags: [.control]))
        // The combo key press cancels session A — no stop edge runs.
        #expect(core.handle(.keyDown) == .interruptCancel)
        // The trigger release is control-free (left is truly up) → heals the bit.
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [])) == .passThrough)
        // Session B: must not latch from the stale bit.
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [.control])) == .start(suppress: false, mode: .plain))
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [])) == .stop(suppress: false, mode: .plain))
    }

    // MARK: - Live latch signal: the recording glyph needs the latch surfaced DURING
    // the hold, not only as the `.translate` at key-up.

    /// LL1 — Control already held at key-down starts directly in `.translate`, so the
    /// recording glyph can be the translate glyph from the very first frame (no plain
    /// flash). No separate live-latch event: the start already carries the mode.
    /// Stated sensitivity: ignore the key-down latch in the start edge (always
    /// `.start(mode: .plain)`) → RED.
    @Test
    func controlHeldAtKeyDownStartsInTranslateMode() {
        var core = HotkeyDecisionCore(trigger: .fn)
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn, .control]))
            == .start(suppress: true, mode: .translate))
    }

    /// LL2 — Control pressed MID-hold surfaces `.translateLatched` on that very event
    /// (fn trigger, foreign left control kc59), so the glyph can switch live instead of
    /// waiting for the `.translate` stop at key-up.
    /// Stated sensitivity: stop surfacing the live latch (return the plain
    /// `.passThrough` for the mid-hold event) → RED.
    @Test
    func midHoldControlSurfacesTranslateLatchLive() {
        var core = HotkeyDecisionCore(trigger: .fn)
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn])) == .start(suppress: true, mode: .plain))
        #expect(core.handle(.flagsChanged(keyCode: 59, flags: [.secondaryFn, .control])) == .translateLatched)
    }

    /// LL3 — the live latch is observed BEFORE the key-code passthrough guard: a
    /// foreign left control (kc59) mid-hold surfaces `.translateLatched` even though
    /// its key code is not the Right ⌘ trigger's own.
    /// Stated sensitivity: move the observe AFTER the key-code guard (kc59 returns
    /// before latching) → the event stays a plain passThrough → RED.
    @Test
    func midHoldForeignControlSurfacesTranslateLatchBeforeKeyCodeGuard() {
        var core = HotkeyDecisionCore(trigger: .rightCommand)
        #expect(core.handle(.flagsChanged(keyCode: 54, flags: [.command])) == .start(suppress: false, mode: .plain))
        #expect(core.handle(.flagsChanged(keyCode: 59, flags: [.command, .control])) == .translateLatched)
    }

    /// LL6 — mirror of LL3 for the Right ⌃ trigger: a foreign LEFT Control (kc59)
    /// pressed mid-hold surfaces `.translateLatched` ON THE PRESS EVENT itself.
    /// L5(b) only asserts the eventual `.translate` stop, so it cannot see a latch
    /// that arrives late — this test pins the LIVE glyph switch for this
    /// trigger+key combo.
    /// Stated sensitivity: the COMPOUND mutant — run `trackLeftControl` after the
    /// latch observation AND reduce the control-trigger latch to
    /// `isLeftControlDown` alone. Each half alone is equivalent (the other defense
    /// covers it); together they delay the latch to the stop edge, the press event
    /// stays a plain `.passThrough`, and only this assert reddens.
    @Test
    func midHoldForeignControlSurfacesTranslateLatchLiveOnRightControlTrigger() {
        var core = HotkeyDecisionCore(trigger: .rightControl)
        #expect(core.handle(.flagsChanged(keyCode: 62, flags: [.control])) == .start(suppress: false, mode: .plain))
        #expect(core.handle(.flagsChanged(keyCode: 59, flags: [.control])) == .translateLatched)
    }

    /// LL4 — the live latch fires EXACTLY ONCE per session: a second held event after
    /// the latch already engaged is an ordinary `.passThrough`, never a repeated
    /// `.translateLatched` (the glyph must not thrash).
    /// Stated sensitivity: drop the `!wasLatched` guard (surface the latch on every
    /// held event while latched) → the second event re-emits `.translateLatched` → RED.
    @Test
    func translateLatchSurfacesOnlyOncePerSession() {
        var core = HotkeyDecisionCore(trigger: .fn)
        _ = core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn]))
        #expect(core.handle(.flagsChanged(keyCode: 59, flags: [.secondaryFn, .control])) == .translateLatched)
        // A further modifier engages while Control is still latched: no re-emit.
        #expect(core.handle(.flagsChanged(keyCode: 56, flags: [.secondaryFn, .control, .shift])) == .passThrough)
    }

    /// LL5 — a plain hold NEVER surfaces a live latch: pressing a non-Control modifier
    /// mid-hold stays a `.passThrough`, and the session still stops `.plain`.
    /// Stated sensitivity: latch on any modifier (not just Control) → the mid-hold
    /// Shift event surfaces `.translateLatched` → RED.
    @Test
    func plainHoldNeverSurfacesTranslateLatch() {
        var core = HotkeyDecisionCore(trigger: .fn)
        _ = core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn]))
        #expect(core.handle(.flagsChanged(keyCode: 56, flags: [.secondaryFn, .shift])) == .passThrough)
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .plain))
    }
}
