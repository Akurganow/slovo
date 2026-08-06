import Testing

import SlovoCore

// The CONFIGURABLE translate key. Either it acts on top of a push-to-talk hold —
// today's Control semantics, now on whichever key is configured — or it stands
// alone as a second push-to-talk key whose holds translate. Loading validation
// guarantees the two configured keys differ, so every configuration here names two
// distinct keys, exactly as the app can produce.
@Suite("Hotkey decision core: configurable translate key")
struct HotkeyDecisionTranslateKeyTests {

    // MARK: - The latch follows the configured key

    /// Control as the PUSH-TO-TALK key must not latch itself: a plain Control hold is
    /// a plain dictation. The translate key is explicitly a non-Control key — with a
    /// colliding pair the whole configuration would fail closed to the defaults and
    /// this test would prove nothing.
    /// Stated sensitivity: re-hardcode the latch to the Control class bit (the
    /// transitional state this test retires) → every Control hold self-latches and
    /// starts AND stops in `.translate` → RED, as proven against that code.
    @Test
    func controlAsMainKeyDoesNotSelfLatchTranslate() {
        var core = HotkeyDecisionCore(
            configuration: HotkeyConfiguration(main: .control, translate: .leftShift, translateIsAdditional: true)
        )
        #expect(core.handle(.flagsChanged(keyCode: 59, flags: [.control])) == .start(suppress: false, mode: .plain))
        // A foreign modifier mid-hold is not the configured translate key.
        #expect(core.handle(.flagsChanged(keyCode: 55, flags: [.control, .command])) == .passThrough)
        #expect(core.handle(.flagsChanged(keyCode: 59, flags: [])) == .stop(suppress: false, mode: .plain))
    }

    /// Control as the push-to-talk key is interruptible like any other passed-through
    /// modifier: a real key press mid-hold cancels the dictation instead of typing
    /// into it — the property a class-level key had no way to exercise before it
    /// could be the main key.
    /// Stated sensitivity: make `classModifier` non-interruptible (report it as
    /// suppressed, as fn is) → the key press leaves as `.passThrough` and the hold
    /// survives → RED.
    @Test
    func controlAsMainKeyIsInterruptCancelledByAKeyPress() {
        var core = HotkeyDecisionCore(
            configuration: HotkeyConfiguration(main: .control, translate: .leftShift, translateIsAdditional: true)
        )
        _ = core.handle(.flagsChanged(keyCode: 59, flags: [.control]))
        #expect(core.handle(.keyDown) == .interruptCancel)
        #expect(!core.isTriggerHeld, "an interrupt releases the held trigger")
    }

    /// A side-specific translate key latches by ITS OWN key code: Right ⌥ latches,
    /// Left ⌥ does not, even though both carry the option class bit.
    /// Stated sensitivity: let a side-specific key engage on its class bit alone
    /// (ignore the key code in `TriggerRecognizer.engages`) → the Left ⌥ event
    /// latches → RED at the second expectation.
    @Test
    func sideSpecificTranslateKeyLatchesOnItsOwnSideOnly() {
        var core = HotkeyDecisionCore(
            configuration: HotkeyConfiguration(main: .fn, translate: .rightOption, translateIsAdditional: true)
        )
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn])) == .start(suppress: true, mode: .plain))
        #expect(core.handle(.flagsChanged(keyCode: 58, flags: [.secondaryFn, .option])) == .passThrough,
                "the other side of the class is not the configured translate key")
        #expect(core.handle(.flagsChanged(keyCode: 61, flags: [.secondaryFn, .option])) == .translateLatched)
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .translate))
    }

    // MARK: - fn in either role (mutual exclusion leaves at most one key fn)

    /// fn as the ADDITIONAL key latches on the fn bit, and the latch is ONE-WAY: the
    /// junk and foreign-modifier events macOS delivers without the fn bit while fn is
    /// physically down must not unlatch the translated dictation.
    /// Stated sensitivity: derive the mode from the current event instead of latching
    /// it (`mode = latchEngages ? .translate : .plain`) → the fn-bit-free junk event
    /// resets the hold to plain → RED at the stop.
    @Test
    func fnAsAdditionalKeyLatchesOnceAndNeverUnlatches() {
        var core = HotkeyDecisionCore(
            configuration: HotkeyConfiguration(main: .rightCommand, translate: .fn, translateIsAdditional: true)
        )
        #expect(core.handle(.flagsChanged(keyCode: 54, flags: [.command])) == .start(suppress: false, mode: .plain))
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.command, .secondaryFn])) == .translateLatched)
        #expect(core.handle(.flagsChanged(keyCode: 0, flags: [.command])) == .passThrough,
                "a junk fn-bit-free event must not unlatch the translated hold")
        #expect(core.handle(.flagsChanged(keyCode: 54, flags: [])) == .stop(suppress: false, mode: .translate))
    }

    /// An ADDITIONAL key pressed with nothing held is none of the decision's
    /// business: it opens no hold and its event passes through to do its normal
    /// system job. fn is the sharpest case — suppression belongs to fn as a SESSION
    /// SOURCE, never to fn as a latch.
    /// Stated sensitivity: let the latch open holds too (treat `.latch` like
    /// `.source` in `openingHold`) → the press opens a suppressed translate hold →
    /// RED on both expectations.
    @Test
    func additionalKeyWithNoHoldPassesThrough() {
        var core = HotkeyDecisionCore(
            configuration: HotkeyConfiguration(main: .rightCommand, translate: .fn, translateIsAdditional: true)
        )
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn])) == .passThrough)
        #expect(!core.isTriggerHeld)
    }

    /// fn as the STANDALONE translate key gets fn's whole machinery for its own
    /// session: its events are suppressed, and a hold that engaged on an external
    /// keyboard's odd key code still stops on the canonical fn code.
    /// Stated sensitivity: judge suppression and release by the MAIN key instead of
    /// the key that opened the hold → the start is not suppressed and the kc63 event
    /// stops nothing → RED.
    @Test
    func fnAsStandaloneTranslateKeyIsSuppressedAndHealsAJunkEngage() {
        var core = HotkeyDecisionCore(
            configuration: HotkeyConfiguration(main: .rightCommand, translate: .fn, translateIsAdditional: false)
        )
        #expect(core.handle(.flagsChanged(keyCode: 100, flags: [.secondaryFn])) == .start(suppress: true, mode: .translate))
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .translate))
    }

    // MARK: - The standalone role: a second push-to-talk key that translates

    /// A standalone translate key opens its own dictation, in `.translate` from the
    /// key-down edge — so the recording glyph shows the translate mode from the first
    /// frame — and stops still carrying `.translate`.
    /// Stated sensitivity: drop the standalone arm from `openingHold` → the key-down
    /// passes through and opens nothing → RED; open the hold in `.plain` → RED.
    @Test
    func standaloneTranslateKeyOpensATranslateDictation() {
        var core = HotkeyDecisionCore(
            configuration: HotkeyConfiguration(main: .fn, translate: .rightOption, translateIsAdditional: false)
        )
        #expect(core.handle(.flagsChanged(keyCode: 61, flags: [.option])) == .start(suppress: false, mode: .translate))
        #expect(core.isTriggerHeld)
        #expect(core.handle(.flagsChanged(keyCode: 61, flags: [])) == .stop(suppress: false, mode: .translate))
        #expect(!core.isTriggerHeld)
    }

    /// A STANDALONE translate key latches nothing: pressed during a main hold it is
    /// inert, and that dictation stays plain.
    /// Stated sensitivity: consult the translate key for the latch in both roles
    /// (drop the `case .latch` restriction in `translateLatchEngages`) → the mid-hold
    /// event reads `.translateLatched` and the hold stops `.translate` → RED.
    @Test
    func standaloneTranslateKeyNeverLatchesOntoTheMainHold() {
        var core = HotkeyDecisionCore(
            configuration: HotkeyConfiguration(main: .fn, translate: .rightOption, translateIsAdditional: false)
        )
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn])) == .start(suppress: true, mode: .plain))
        #expect(core.handle(.flagsChanged(keyCode: 61, flags: [.secondaryFn, .option])) == .passThrough)
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .plain))
    }

    /// With two session sources, the key that went down FIRST owns the dictation and
    /// the other one is fully inert until idle — in both orders. The second key
    /// neither opens a session of its own nor ends the running one, and the mode is
    /// the owner's throughout.
    /// Stated sensitivity: let the hold be judged by the main key rather than by the
    /// key that opened it → in the translate-first order the fn events end the
    /// translate hold → RED; consult `openingHold` while a hold is open → the second
    /// key replaces the running session → RED.
    @Test
    func theFirstKeyDownOwnsTheDictation() {
        let configuration = HotkeyConfiguration(main: .fn, translate: .rightOption, translateIsAdditional: false)

        // Main first: the translate key's own down and up events are inert.
        var mainFirst = HotkeyDecisionCore(configuration: configuration)
        #expect(mainFirst.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn])) == .start(suppress: true, mode: .plain))
        #expect(mainFirst.handle(.flagsChanged(keyCode: 61, flags: [.secondaryFn, .option])) == .passThrough)
        #expect(mainFirst.handle(.flagsChanged(keyCode: 61, flags: [.secondaryFn])) == .passThrough)
        #expect(mainFirst.isTriggerHeld, "the translate key's release must not end the main dictation")
        #expect(mainFirst.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .plain))

        // Translate first: the main key's own down and up events are inert.
        var translateFirst = HotkeyDecisionCore(configuration: configuration)
        #expect(translateFirst.handle(.flagsChanged(keyCode: 61, flags: [.option])) == .start(suppress: false, mode: .translate))
        #expect(translateFirst.handle(.flagsChanged(keyCode: 63, flags: [.option, .secondaryFn])) == .passThrough)
        #expect(translateFirst.handle(.flagsChanged(keyCode: 63, flags: [.option])) == .passThrough)
        #expect(translateFirst.isTriggerHeld, "the main key's release must not end the translate dictation")
        #expect(translateFirst.handle(.flagsChanged(keyCode: 61, flags: [])) == .stop(suppress: false, mode: .translate))
    }

    /// A standalone translate dictation is interrupt-cancelled by a real key press
    /// exactly like a main one: the user reached for a shortcut, so the dictation
    /// dies silently. Its interruptibility is the TRANSLATE key's — here a
    /// passed-through modifier, while the main key (fn) is not interruptible at all.
    /// Stated sensitivity: read interruptibility from the main key instead of the key
    /// that opened the hold (the pre-standalone shape) → fn's non-interruptibility
    /// answers for a Left ⇧ hold and the press passes through → RED.
    @Test
    func standaloneTranslateDictationIsInterruptCancelled() {
        var core = HotkeyDecisionCore(
            configuration: HotkeyConfiguration(main: .fn, translate: .leftShift, translateIsAdditional: false)
        )
        #expect(core.handle(.flagsChanged(keyCode: 56, flags: [.shift])) == .start(suppress: false, mode: .translate))
        #expect(core.handle(.keyDown) == .interruptCancel)
        #expect(!core.isTriggerHeld)
    }

    // MARK: - A cancelled hold stays disarmed until its key is physically released

    /// After an interrupt-cancel the cancelled key is STILL DOWN, and a class-detected
    /// key is recognized by its modifier bit alone — so every later modifier press
    /// carries that bit and would re-engage it. Reaching for ⌃⇧V after a cancelled ⌃
    /// hold must not open a dictation the user never asked for: only releasing the key
    /// re-arms it.
    /// Stated sensitivity: end the interrupt-cancel by dropping the hold outright (no
    /// disarmed state) → the ⌘ press re-opens a dictation → RED, as proven against
    /// that code; clear the disarm on any event rather than on the key's release → the
    /// ⌘ release re-opens it → RED.
    @Test
    func cancelledControlMainKeyStaysDisarmedUntilReleased() {
        var core = HotkeyDecisionCore(
            configuration: HotkeyConfiguration(main: .control, translate: .leftShift, translateIsAdditional: true)
        )
        #expect(core.handle(.flagsChanged(keyCode: 59, flags: [.control])) == .start(suppress: false, mode: .plain))
        #expect(core.handle(.keyDown) == .interruptCancel)
        #expect(!core.isTriggerHeld)

        // ⌘ joins and leaves while Control is still physically down.
        #expect(core.handle(.flagsChanged(keyCode: 55, flags: [.control, .command])) == .passThrough)
        #expect(core.handle(.flagsChanged(keyCode: 55, flags: [.control])) == .passThrough)
        #expect(!core.isTriggerHeld)

        // Control comes up: only now is the key armed again.
        #expect(core.handle(.flagsChanged(keyCode: 59, flags: [])) == .passThrough)
        #expect(core.handle(.flagsChanged(keyCode: 59, flags: [.control])) == .start(suppress: false, mode: .plain))
    }

    /// The same for a STANDALONE translate key, which opens dictations of its own: a
    /// cancelled Control hold must not translate-dictate on the next modifier press.
    /// While it waits to be released it owns the core, so the OTHER push-to-talk key
    /// stays inert too — with the cancelled key still down, a press of it is part of a
    /// shortcut, not a request to dictate.
    /// Stated sensitivity: end the interrupt-cancel by dropping the hold outright → the
    /// ⇧ press opens a translate dictation → RED, as proven against that code; disarm
    /// only the cancelled key instead of the core → the fn press opens a plain one →
    /// RED.
    @Test
    func cancelledStandaloneControlKeyStaysDisarmedUntilReleased() {
        var core = HotkeyDecisionCore(
            configuration: HotkeyConfiguration(main: .fn, translate: .control, translateIsAdditional: false)
        )
        #expect(core.handle(.flagsChanged(keyCode: 59, flags: [.control])) == .start(suppress: false, mode: .translate))
        #expect(core.handle(.keyDown) == .interruptCancel)

        #expect(core.handle(.flagsChanged(keyCode: 56, flags: [.control, .shift])) == .passThrough)
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.control, .secondaryFn])) == .passThrough,
                "the other push-to-talk key must stay inert while the cancelled key is down")
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.control])) == .passThrough)

        #expect(core.handle(.flagsChanged(keyCode: 59, flags: [])) == .passThrough)
        #expect(core.handle(.flagsChanged(keyCode: 59, flags: [.control])) == .start(suppress: false, mode: .translate))
    }

    /// A live key change starts from a clean state, the disarm included: whatever the
    /// user was holding when they changed the setting is no longer the core's business.
    /// Stated sensitivity: carry the disarmed state across `reconfigure` → the press
    /// after it is swallowed → RED.
    @Test
    func reconfigureArmsACancelledKeyAgain() {
        let configuration = HotkeyConfiguration(main: .control, translate: .leftShift, translateIsAdditional: true)
        var core = HotkeyDecisionCore(configuration: configuration)
        _ = core.handle(.flagsChanged(keyCode: 59, flags: [.control]))
        #expect(core.handle(.keyDown) == .interruptCancel)

        core.reconfigure(to: configuration)

        #expect(core.handle(.flagsChanged(keyCode: 55, flags: [.control, .command])) == .start(suppress: false, mode: .plain))
    }

    /// Tap death synthesizes a stop in the mode the dying hold was in — for a
    /// standalone translate dictation and for a latched one alike. The recording
    /// glyph has been showing that mode, so an emergency exit must not quietly
    /// downgrade the dictation to plain on its way out.
    /// Stated sensitivity: hardcode the synthesized stop to `.plain` (or to `nil`)
    /// → RED on both halves.
    @Test
    func tapDeathSynthesizesAStopInTheHeldMode() {
        var standalone = HotkeyDecisionCore(
            configuration: HotkeyConfiguration(main: .fn, translate: .rightOption, translateIsAdditional: false)
        )
        _ = standalone.handle(.flagsChanged(keyCode: 61, flags: [.option]))
        #expect(standalone.handle(.tapDisabled) == .resync(synthesizedStop: .translate))

        var latched = makeDecisionCore(main: .fn)
        _ = latched.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn]))
        _ = latched.handle(.flagsChanged(keyCode: 59, flags: [.secondaryFn, .control]))
        #expect(latched.handle(.tapDisabled) == .resync(synthesizedStop: .translate))
    }

    // MARK: - Live reconfiguration

    /// Changing the translate key rebuilds the latch: the old key stops latching and
    /// the new one starts, on the very next hold.
    /// Stated sensitivity: rebuild only the push-to-talk key in `reconfigure`
    /// (keeping the latch built at init) → Control still latches and Left ⇧ does not
    /// → RED on both mid-hold expectations.
    @Test
    func reconfigureRebuildsTheLatchKey() {
        var core = makeDecisionCore(main: .fn)
        core.reconfigure(to: HotkeyConfiguration(main: .fn, translate: .leftShift, translateIsAdditional: true))

        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn])) == .start(suppress: true, mode: .plain))
        #expect(core.handle(.flagsChanged(keyCode: 59, flags: [.secondaryFn, .control])) == .passThrough,
                "the retired translate key must no longer latch")
        #expect(core.handle(.flagsChanged(keyCode: 56, flags: [.secondaryFn, .shift])) == .translateLatched)
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .translate))
    }

    /// Switching the translate key's ROLE applies live too, and reconfiguring mid-hold
    /// drops the hold: the key that latched a moment ago now opens its own translate
    /// dictation.
    /// Stated sensitivity: keep the translate role across `reconfigure` → the Left ⇧
    /// press latches onto nothing and passes through instead of opening a translate
    /// dictation → RED; keep the open hold across `reconfigure` → the press is judged
    /// mid-hold → RED.
    @Test
    func reconfigureRebuildsTheTranslateRoleAndDropsTheHold() {
        var core = HotkeyDecisionCore(
            configuration: HotkeyConfiguration(main: .fn, translate: .leftShift, translateIsAdditional: true)
        )
        _ = core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn]))

        core.reconfigure(to: HotkeyConfiguration(main: .fn, translate: .leftShift, translateIsAdditional: false))

        #expect(!core.isTriggerHeld, "a live key change must drop the hold judged against the old configuration")
        #expect(core.handle(.flagsChanged(keyCode: 56, flags: [.shift])) == .start(suppress: false, mode: .translate))
    }
}
