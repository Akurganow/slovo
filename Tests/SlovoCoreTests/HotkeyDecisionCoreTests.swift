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

    // MARK: - Per-side triggers: each ⌘⌥⇧ trigger matches exactly ONE side-specific
    // key code. While held, an event naming the trigger's OWN key code is its
    // toggle — it stops the session regardless of the class bit (the other side
    // may still hold it); while not held, a start needs key code AND class bit.

    /// The trigger table, all six side cases: each starts on its own key code +
    /// class bit and stops on its own key code without the bit.
    /// Stated sensitivity: swap any key code in the trigger table (e.g. Left ⌘ 55
    /// ↔ Right ⌘ 54) → that row's `.start` reads `.passThrough` → RED.
    @Test
    func perSideTriggerStartsAndStops() {
        let cases: [(HotkeyTrigger, Int64, HotkeyModifierFlags)] = [
            (.leftCommand, 55, .command),
            (.rightCommand, 54, .command),
            (.leftOption, 58, .option),
            (.rightOption, 61, .option),
            (.leftShift, 56, .shift),
            (.rightShift, 60, .shift),
        ]
        for (trigger, keyCode, flag) in cases {
            var core = HotkeyDecisionCore(trigger: trigger)
            #expect(core.handle(.flagsChanged(keyCode: keyCode, flags: [flag])) == .start(suppress: false, mode: .plain),
                    "\(trigger) must start on its own key code \(keyCode)")
            #expect(core.isTriggerHeld)
            #expect(core.handle(.flagsChanged(keyCode: keyCode, flags: [])) == .stop(suppress: false, mode: .plain),
                    "\(trigger) must stop on its own key code \(keyCode)")
            #expect(!core.isTriggerHeld)
        }
    }

    /// Releasing the trigger key while the OTHER side of the same class is still
    /// held must STOP the session: the trigger's own key-code event is its toggle
    /// even though the class bit is still set (the other side holds it). Without
    /// the toggle rule the release is missed and the session wedges — the latent
    /// stuck-session bug proven RED on the pre-change matcher (right ⌘ released
    /// while left ⌘ typed on: `.passThrough`, `isTriggerHeld` stuck true).
    /// Stated sensitivity: revert the held-side toggle to the class-bit edge
    /// (stop only when the bit clears) → the third event reads `.passThrough` and
    /// held stays true → RED.
    @Test
    func crossSideReleaseStopsWhileOtherSideHolds() {
        // (trigger, its own key code, the joining other side's key code, class bit)
        let cases: [(HotkeyTrigger, Int64, Int64, HotkeyModifierFlags)] = [
            (.rightCommand, 54, 55, .command),
            (.rightOption, 61, 58, .option),
            (.leftOption, 58, 61, .option),
            (.leftShift, 56, 60, .shift),
        ]
        for (trigger, own, other, flag) in cases {
            var core = HotkeyDecisionCore(trigger: trigger)
            #expect(core.handle(.flagsChanged(keyCode: own, flags: [flag])) == .start(suppress: false, mode: .plain),
                    "\(trigger): the hold starts on its own key code")
            #expect(core.handle(.flagsChanged(keyCode: other, flags: [flag])) == .passThrough,
                    "\(trigger): the other side joining mid-hold is not ours")
            #expect(core.handle(.flagsChanged(keyCode: own, flags: [flag])) == .stop(suppress: false, mode: .plain),
                    "\(trigger): its own release must stop even while the other side holds the class bit")
            #expect(!core.isTriggerHeld, "\(trigger): the released trigger must not stay latched")
        }
    }

    /// A start still requires the class bit: while NOT held, the trigger's own
    /// key code with empty flags is a release echo, not a press.
    /// Green by design. Stated RED target: reduce `engaged` to the key-code match
    /// alone (a bare toggle) → the idle release event starts a phantom session →
    /// RED.
    @Test
    func startRequiresClassBit() {
        let cases: [(HotkeyTrigger, Int64)] = [(.rightCommand, 54), (.leftOption, 58)]
        for (trigger, keyCode) in cases {
            var core = HotkeyDecisionCore(trigger: trigger)
            #expect(core.handle(.flagsChanged(keyCode: keyCode, flags: [])) == .passThrough,
                    "\(trigger): an own-key-code event without the class bit must not start")
            #expect(!core.isTriggerHeld)
        }
    }

    /// Left-side mirrors of `wrongSideModifierDoesNotStart`: a LEFT trigger must
    /// ignore the RIGHT side's key code even with the class bit set.
    /// Green by design. Stated RED target: blanket cross-side matching (either
    /// side matches every trigger of its class) → the right-side event starts a
    /// left trigger → RED.
    @Test
    func leftTriggersIgnoreTheRightSideKeyCode() {
        let cases: [(HotkeyTrigger, Int64, HotkeyModifierFlags)] = [
            (.leftCommand, 54, .command),
            (.leftShift, 60, .shift),
        ]
        for (trigger, rightKeyCode, flag) in cases {
            var core = HotkeyDecisionCore(trigger: trigger)
            #expect(core.handle(.flagsChanged(keyCode: rightKeyCode, flags: [flag])) == .passThrough,
                    "\(trigger) must not start on the right side's key code")
            #expect(!core.isTriggerHeld)
        }
    }

    /// A Left ⌥ hold is interrupted by a combo key press like any other
    /// passthrough-modifier hold: the in-flight dictation cancels silently.
    /// Stated sensitivity: drop the left-side trigger from the interrupt path
    /// (kc58 never starts, so nothing is held at the key press) → the `.keyDown`
    /// reads `.passThrough` → RED.
    @Test
    func leftOptionHoldIsInterruptCancelledByAKeyPress() {
        var core = HotkeyDecisionCore(trigger: .leftOption)
        _ = core.handle(.flagsChanged(keyCode: 58, flags: [.option]))
        #expect(core.handle(.keyDown) == .interruptCancel)
        #expect(!core.isTriggerHeld, "an interrupt releases the held trigger")
    }

    /// Right-side wrong-side guard for ⇧: the Right ⇧ trigger must ignore LEFT
    /// Shift's key code (56) even with the class bit set.
    /// Green by design. Stated RED target: blanket cross-side matching → left
    /// Shift starts dictation → RED.
    @Test
    func rightShiftStaysRightOnly() {
        var core = HotkeyDecisionCore(trigger: .rightShift)
        #expect(core.handle(.flagsChanged(keyCode: 56, flags: [.shift])) == .passThrough)
        #expect(!core.isTriggerHeld)
    }

    /// Tap death while a trigger is held resyncs by synthesizing an up, so
    /// push-to-talk can never stick "down" after the tap is re-enabled.
    /// Stated sensitivity: drop the synthesized up (return `.resync(synthesizeUp:
    /// false)` when held) → the held trigger is not released → RED.
    @Test
    func tapDeathWhileHeldSynthesizesUp() {
        var core = HotkeyDecisionCore(trigger: .rightShift)
        _ = core.handle(.flagsChanged(keyCode: 60, flags: [.shift]))
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
            (.leftOption, 58, .option),
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
    /// session on the new trigger stops `.plain`.
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
    /// (a `.passthroughModifier` trigger — only those have an interrupt path)
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
