import Testing

import SlovoCore

// The fn trigger's RELEASE rule. The start edge is unchanged (the `.secondaryFn`
// flag edge, any key code), but a mid-hold `flagsChanged` that merely LACKS the
// fn bit is not proof the fn key was released — macOS delivers junk and foreign-
// modifier events without the bit while fn is still physically down. The session
// must stop only when the fn-bit-free event's key code names the fn key itself:
// the latched session-start key code, or the canonical fn key code 63.
@Suite("Hotkey decision core: fn release")
struct HotkeyDecisionFnReleaseTests {

    /// A junk `flagsChanged` (key code 0, no flags) mid-hold must NOT stop the fn
    /// session — kc0 is not the fn key. The real kc63 release still stops.
    /// Stated sensitivity: stop on ANY fn-bit-free event (today's behavior) → the
    /// kc0 event reads `.stop` instead of `.passThrough` → RED.
    @Test
    func fnMidHoldJunkFlagsEventDoesNotStop() {
        var core = makeDecisionCore(main: .fn)
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn])) == .start(suppress: true, mode: .plain))
        #expect(core.handle(.flagsChanged(keyCode: 0, flags: [])) == .passThrough)
        #expect(core.isTriggerHeld, "a junk fn-bit-free event must not release the held fn session")
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .plain))
    }

    /// A foreign modifier event whose flags glitched the fn bit away (left Control,
    /// kc59, `.control` only) mid-hold must not stop the session — AND its Control
    /// still latches translate live, so the stop carries `.translate`.
    /// Stated sensitivity: stop on any fn-bit-free event (today's behavior) → the
    /// kc59 event reads `.stop` instead of `.translateLatched` → RED.
    @Test
    func fnMidHoldForeignModifierMissingFnBitDoesNotStopButStillLatches() {
        var core = makeDecisionCore(main: .fn)
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn])) == .start(suppress: true, mode: .plain))
        #expect(core.handle(.flagsChanged(keyCode: 59, flags: [.control])) == .translateLatched)
        #expect(core.isTriggerHeld, "a foreign-modifier fn-bit-free event must not release the held fn session")
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .translate))
    }

    /// An fn session STARTED on a non-canonical key code (external keyboards report
    /// odd codes) stops on that same latched key code, not only on 63.
    /// Green today (any fn-bit-free event stops). Stated RED target: narrow the
    /// release to the fixed kc63 arm only → the kc100 release reads `.passThrough`
    /// instead of `.stop` → RED (protects the external-keyboard fallback).
    @Test
    func fnSessionStartedOnOddKeyCodeStopsOnSameKeyCode() {
        var core = makeDecisionCore(main: .fn)
        #expect(core.handle(.flagsChanged(keyCode: 100, flags: [.secondaryFn])) == .start(suppress: true, mode: .plain))
        #expect(core.handle(.flagsChanged(keyCode: 100, flags: [])) == .stop(suppress: true, mode: .plain))
    }

    /// An fn session whose START arrived on a junk key code (kc0) still heals on
    /// the canonical kc63 release, so a corrupted start can never wedge the session
    /// open. The held kc63 event with the fn bit still set is a plain passthrough.
    /// Green today. Stated RED target: drop the fixed-63 release arm (release on
    /// the latched start code only) → the kc63 release reads `.passThrough`, the
    /// session never stops → RED.
    @Test
    func fnJunkStartHealsOnCanonicalFnRelease() {
        var core = makeDecisionCore(main: .fn)
        #expect(core.handle(.flagsChanged(keyCode: 0, flags: [.secondaryFn])) == .start(suppress: true, mode: .plain))
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [.secondaryFn])) == .passThrough)
        #expect(core.handle(.flagsChanged(keyCode: 63, flags: [])) == .stop(suppress: true, mode: .plain))
    }
}
