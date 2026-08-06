import Testing

import SlovoCore

/// The shipping default shape: `main` as the push-to-talk key, Control as the
/// ADDITIONAL translate key. Shared by the hotkey decision suites; a test about
/// another translate role builds its configuration itself.
func controlLatchConfiguration(main: HotkeyTrigger) -> HotkeyConfiguration {
    HotkeyConfiguration(main: main, translate: .control, translateIsAdditional: true)
}

func makeDecisionCore(main: HotkeyTrigger) -> HotkeyDecisionCore {
    HotkeyDecisionCore(configuration: controlLatchConfiguration(main: main))
}

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
        var core = makeDecisionCore(main: .fn)
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
        var core = makeDecisionCore(main: .fn)
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
        var core = makeDecisionCore(main: .rightCommand)
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
        var core = makeDecisionCore(main: .rightCommand)
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
        var core = makeDecisionCore(main: .rightCommand)
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
        var core = makeDecisionCore(main: .rightCommand)
        #expect(core.handle(.flagsChanged(keyCode: 61, flags: [.command])) == .passThrough)
        #expect(!core.isTriggerHeld)
    }

    /// Control as the push-to-talk key is class-level: EITHER Control key opens the
    /// hold and clearing the class bit ends it — there is no side to name. The
    /// translate key is deliberately a non-Control key, because naming Control in
    /// both roles is rejected where the configuration is loaded and a colliding
    /// pair would prove nothing here.
    /// Stated sensitivity: recognize `.control` as any other kind (the fn bit, or a
    /// side-specific key code) → the class-bit event opens no hold → RED. Release a
    /// class-level key on its own key code instead of on the class bit clearing →
    /// the second event never stops the hold → RED.
    @Test
    func controlMainKeyHoldsOnTheModifierClassFromEitherSide() {
        let configuration = HotkeyConfiguration(main: .control, translate: .leftShift, translateIsAdditional: true)
        for keyCode: Int64 in [59, 62] {
            var core = HotkeyDecisionCore(configuration: configuration)
            #expect(core.handle(.flagsChanged(keyCode: keyCode, flags: [.control])) == .start(suppress: false, mode: .plain),
                    "Control key code \(keyCode) must open the hold, passed through")
            #expect(core.handle(.flagsChanged(keyCode: keyCode, flags: [])) == .stop(suppress: false, mode: .plain),
                    "clearing the Control class bit must end the hold")
        }
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
            var core = makeDecisionCore(main: trigger)
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
            var core = makeDecisionCore(main: trigger)
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
            var core = makeDecisionCore(main: trigger)
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
            var core = makeDecisionCore(main: trigger)
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
        var core = makeDecisionCore(main: .leftOption)
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
        var core = makeDecisionCore(main: .rightShift)
        #expect(core.handle(.flagsChanged(keyCode: 56, flags: [.shift])) == .passThrough)
        #expect(!core.isTriggerHeld)
    }

    /// Tap death while a trigger is held resyncs by synthesizing a stop, so
    /// push-to-talk can never stick "down" after the tap is re-enabled.
    /// Stated sensitivity: drop the synthesized stop (return `.resync(synthesizedStop:
    /// nil)` when held) → the held trigger is not released → RED.
    @Test
    func tapDeathWhileHeldSynthesizesStop() {
        var core = makeDecisionCore(main: .rightShift)
        _ = core.handle(.flagsChanged(keyCode: 60, flags: [.shift]))
        #expect(core.handle(.tapDisabled) == .resync(synthesizedStop: .plain))
        #expect(!core.isTriggerHeld)
    }

    /// Tap death with nothing held resyncs without a synthetic stop.
    /// Stated sensitivity: always synthesize a stop → a spurious stop is emitted
    /// when idle → RED.
    @Test
    func tapDeathWhileIdleDoesNotSynthesizeStop() {
        var core = makeDecisionCore(main: .fn)
        #expect(core.handle(.tapDisabled) == .resync(synthesizedStop: nil))
    }

    /// Reconfiguring to a new trigger resets the held state, so a live key change
    /// starts clean.
    /// Stated sensitivity: keep the held bit across reconfigure → the next event is
    /// judged against stale held state → RED.
    @Test
    func reconfigureResetsHeldState() {
        var core = makeDecisionCore(main: .rightCommand)
        _ = core.handle(.flagsChanged(keyCode: 54, flags: [.command]))
        core.reconfigure(to: controlLatchConfiguration(main: .rightShift))
        #expect(!core.isTriggerHeld)
        #expect(core.handle(.flagsChanged(keyCode: 60, flags: [.shift])) == .start(suppress: false, mode: .plain))
    }

    // MARK: - The additional translate key (Control by default): held at any moment
    // of the hold, it latches the session's stop into `.translate` (default `.plain`).

    /// Plain-path baseline: a hold with NO control at any point stops in `.plain`.
    /// Stated sensitivity: default the latch to `.translate` (or latch when control
    /// is absent) → this stop reads `.translate` → RED.
    @Test
    func heldWithoutControlStaysPlain() {
        var core = makeDecisionCore(main: .fn)
        _ = core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn]))
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .plain))
    }

    /// L2 — Control pressed MID-hold latches translate: fn down, then a control key
    /// goes down while fn is still held, then fn up ⇒ `.stop(mode: .translate)`.
    /// Stated sensitivity: never observe control during the hold → the stop stays
    /// `.plain` → RED.
    @Test
    func controlPressedMidHoldLatchesTranslate() {
        var core = makeDecisionCore(main: .fn)
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
    /// Stated sensitivity: drop the latch read in `openingHold` (start every hold in
    /// `.plain`) → nothing latches this session → the control-free release stops
    /// `.plain` → RED.
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
            var core = makeDecisionCore(main: trigger)
            let suppress = trigger == .fn
            #expect(core.handle(.flagsChanged(keyCode: keyCode, flags: [flag, .control])) == .start(suppress: suppress, mode: .translate),
                    "\(trigger) must still start (in .translate) when control is already held at key-down")
            // Control already released before key-up: only the start edge could have latched.
            #expect(core.handle(.flagsChanged(keyCode: keyCode, flags: [])) == .stop(suppress: suppress, mode: .translate),
                    "\(trigger): control held at key-down must latch the session's stop into .translate")
        }
    }

    /// L4 — a FOREIGN key's event latches: with a right-modifier trigger, a
    /// non-trigger control key (left control, key code 59) engages mid-hold, and the
    /// latch is read on that event even though it belongs to no configured hold key.
    /// Passes on the correct code. The trigger-release event drops `.control` so this
    /// test alone isolates the foreign-event latch: a release still carrying
    /// `.control` would re-latch at the stop edge and mask the mutation.
    /// Stated sensitivity: consult the latch only on the hold key's OWN events (add
    /// `hold.key.engages(...)` to `latchesNow`) → the foreign kc59 event never
    /// latches, and the control-free release cannot → the stop stays `.plain` → RED.
    @Test
    func foreignKeyEventLatchesTranslateOntoTheHold() {
        var core = makeDecisionCore(main: .rightCommand)
        #expect(core.handle(.flagsChanged(keyCode: 54, flags: [.command])) == .start(suppress: false, mode: .plain))
        // Left control (non-trigger key code) engages while Right ⌘ is held.
        _ = core.handle(.flagsChanged(keyCode: 59, flags: [.command, .control]))
        // Release the trigger with Control already gone: no stop-edge re-latch.
        #expect(core.handle(.flagsChanged(keyCode: 54, flags: [])) == .stop(suppress: false, mode: .translate))
    }

    /// L5 — "at any moment of the hold" includes the very event that ENDS it: the
    /// translate key pressed as the trigger comes up still turns that dictation into
    /// a translation, so a fast hold does not lose the intent by a millisecond.
    /// Stated sensitivity: read the latch only after the hold key has judged the
    /// event (move `latchesNow` inside the non-release branch) → the stop is built
    /// from the pre-event mode → `.plain` → RED.
    @Test
    func theLatchStillCountsOnTheEventThatEndsTheHold() {
        var core = makeDecisionCore(main: .fn)
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn])) == .start(suppress: true, mode: .plain))
        // fn comes up on the same event that first carries Control.
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.control])) == .stop(suppress: true, mode: .translate))
    }

    /// L6 — the latch is per-session across a NORMAL stop→start: a translate-latched
    /// hold does not bleed into the next hold. Session A (with control) latches
    /// translate; session B (no control) on the SAME core stops `.plain`. Passes on
    /// the correct code.
    /// Stated sensitivity: the session-B `.plain` result is guarded by the stop edge
    /// clearing the session — stop returning the decision without `session = nil` and
    /// session B inherits session A's `.translate` → RED. That the mode cannot outlive
    /// a hold at all (it is a field of `Session`) is owned by the F2 abnormal-exit
    /// tests below.
    @Test
    func controlLatchResetsPerSession() {
        var core = makeDecisionCore(main: .fn)

        // Session A: control mid-hold latches translate.
        _ = core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn]))
        _ = core.handle(.flagsChanged(keyCode: 59, flags: [.secondaryFn, .control]))
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .translate))

        // Session B: no control at all → plain.
        _ = core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn]))
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .plain))
    }

    /// F2(a) — a latched hold that ends ABNORMALLY via `.tapDisabled` must not leave a
    /// sticky translate: the next fresh no-Control hold stops `.plain`. Passes on the
    /// correct code. The tap-death path emits no `.stop`, so nothing but dropping the
    /// whole session — the mode lives INSIDE it — keeps the leftover latch from
    /// bleeding over, while the emergency stop still carries the dead hold's mode.
    /// Stated sensitivity: leave `session` standing on the tap-death path → the
    /// leftover `.translate` is still held when the next hold runs → RED.
    @Test
    func latchDoesNotSurviveTapDisabledAbnormalExit() {
        var core = makeDecisionCore(main: .fn)

        // Session 1: Control held at key-down latches translate...
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn, .control])) == .start(suppress: true, mode: .translate))
        // ...but the hold ends abnormally (tap death), emitting no stop.
        #expect(core.handle(.tapDisabled) == .resync(synthesizedStop: .translate))

        // Session 2: a fresh no-Control hold must stop plain.
        _ = core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn]))
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .plain))
    }

    /// F2(b) — a latched hold that ends ABNORMALLY via a `.keyDown` interrupt-cancel
    /// (a `.passthroughModifier` trigger — only those have an interrupt path) must not
    /// leave a sticky translate. Passes on the correct code. The interrupt path emits
    /// `.interruptCancel`, not `.stop`, and the cancelled hold keeps its key disarmed
    /// until it comes up — so the next hold's mode can only come from its own edges.
    /// Stated sensitivity: carry the cancelled hold's mode over to whatever opens
    /// next → the second, control-free hold stops `.translate` → RED.
    @Test
    func latchDoesNotSurviveInterruptCancelAbnormalExit() {
        var core = makeDecisionCore(main: .rightCommand)

        // Session 1: Control also held at key-down latches translate...
        #expect(core.handle(.flagsChanged(keyCode: 54, flags: [.command, .control])) == .start(suppress: false, mode: .translate))
        // ...but a non-trigger key goes down → interrupt-cancel (no stop).
        #expect(core.handle(.keyDown) == .interruptCancel)
        // The cancelled key comes up; only then may a new hold open.
        #expect(core.handle(.flagsChanged(keyCode: 54, flags: [])) == .passThrough)

        // Session 2: a fresh no-Control hold must stop plain.
        _ = core.handle(.flagsChanged(keyCode: 54, flags: [.command]))
        #expect(core.handle(.flagsChanged(keyCode: 54, flags: [])) == .stop(suppress: false, mode: .plain))
    }

    // MARK: - Live latch signal: the recording glyph needs the latch surfaced DURING
    // the hold, not only as the `.translate` at key-up.

    /// LL1 — Control already held at key-down starts directly in `.translate`, so the
    /// recording glyph can be the translate glyph from the very first frame (no plain
    /// flash). No separate live-latch event: the start already carries the mode.
    /// Stated sensitivity: drop the latch read in `openingHold` (open every hold in
    /// `.plain`) → RED.
    @Test
    func controlHeldAtKeyDownStartsInTranslateMode() {
        var core = makeDecisionCore(main: .fn)
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
        var core = makeDecisionCore(main: .fn)
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn])) == .start(suppress: true, mode: .plain))
        #expect(core.handle(.flagsChanged(keyCode: 59, flags: [.secondaryFn, .control])) == .translateLatched)
    }

    /// LL3 — the live latch is read on FOREIGN events too: a left control (kc59)
    /// mid-hold surfaces `.translateLatched` even though its key code is not the
    /// Right ⌘ trigger's own.
    /// Stated sensitivity: consult the latch only on the hold key's OWN events (add
    /// `hold.key.engages(...)` to `latchesNow`) → the kc59 event leaves as a plain
    /// passThrough → RED.
    @Test
    func midHoldForeignControlSurfacesTranslateLatchLiveToo() {
        var core = makeDecisionCore(main: .rightCommand)
        #expect(core.handle(.flagsChanged(keyCode: 54, flags: [.command])) == .start(suppress: false, mode: .plain))
        #expect(core.handle(.flagsChanged(keyCode: 59, flags: [.command, .control])) == .translateLatched)
    }

    /// LL4 — the live latch fires EXACTLY ONCE per session: a second held event after
    /// the latch already engaged is an ordinary `.passThrough`, never a repeated
    /// `.translateLatched` (the glyph must not thrash).
    /// Stated sensitivity: drop the `hold.mode == .plain` half of `latchesNow` (let an
    /// already-translate hold latch again) → the second event re-emits
    /// `.translateLatched` → RED.
    @Test
    func translateLatchSurfacesOnlyOncePerSession() {
        var core = makeDecisionCore(main: .fn)
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
        var core = makeDecisionCore(main: .fn)
        _ = core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn]))
        #expect(core.handle(.flagsChanged(keyCode: 56, flags: [.secondaryFn, .shift])) == .passThrough)
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .plain))
    }
}
