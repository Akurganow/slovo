import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Idle-release after keepWarm and immediate release at keepWarm == 0,
// plus supersede-pending-release and release idempotency.
//
// Contract under test: the implementer restores the production `ModelLifecycle`
// plus the `ModelLoading`/`Clock` seams in
// `Sources/SlovoCore/ASR/ModelLifecycle.swift` (deleted by the abandoned
// Apple-Speech migration). RED mode now is a COMPILE failure — `ModelLifecycle`
// (and the `ModelLoading`/`SpeechDecoding` seams the `FakeSpeechEngine` conforms
// to) do not exist in the working tree yet.
@Suite("Model lifecycle")
struct ModelLifecycleTests {

    /// After `didFinishUse()`, advancing the clock PAST keepWarmSeconds and
    /// calling `tick()` releases the model; within the window it stays loaded.
    /// Stated sensitivity: never release → the model stays loaded past the window
    /// → RED.
    @Test
    func releasesAfterIdleExceedsKeepWarm() async throws {
        let engine = FakeSpeechEngine()
        let clock = FakeClock(start: 0)
        let lifecycle = ModelLifecycle(model: engine, keepWarmSeconds: 120, clock: clock)

        try await lifecycle.willUse()
        #expect(engine.isLoaded, "willUse must load the model")

        lifecycle.didFinishUse()

        // Within the keep-warm window: still loaded.
        clock.advance(by: 60)
        lifecycle.tick()
        #expect(engine.isLoaded, "model must stay loaded within the 120 s keep-warm window")

        // Past the window: released.
        clock.advance(by: 61)  // total idle 121 s > 120
        lifecycle.tick()
        #expect(!engine.isLoaded, "model must be released once idle exceeds keepWarmSeconds")
        #expect(engine.releaseCount >= 1, "release() must have been called")
    }

    /// With keepWarmSeconds == 0, `didFinishUse()` releases immediately (no
    /// tick needed).
    /// Stated sensitivity: keep warm despite keepWarm == 0 → still loaded → RED.
    @Test
    func releasesImmediatelyWhenKeepWarmIsZero() async throws {
        let engine = FakeSpeechEngine()
        let clock = FakeClock(start: 0)
        let lifecycle = ModelLifecycle(model: engine, keepWarmSeconds: 0, clock: clock)

        try await lifecycle.willUse()
        #expect(engine.isLoaded, "willUse must load the model")

        lifecycle.didFinishUse()
        #expect(!engine.isLoaded, "keepWarmSeconds == 0 must release immediately on didFinishUse()")
    }

    /// A new use within the keep-warm window supersedes the pending release: the
    /// model must NOT be torn down while it is back in use.
    /// Stated sensitivity: drop the `idleSince = nil` reset in `willUse()` → the
    /// stale idle timer still fires on the next `tick()` and releases a model that
    /// is in use → RED.
    @Test
    func newUseBeforeExpirySupersedesPendingRelease() async throws {
        let engine = FakeSpeechEngine()
        let clock = FakeClock(start: 0)
        let lifecycle = ModelLifecycle(model: engine, keepWarmSeconds: 120, clock: clock)

        try await lifecycle.willUse()
        lifecycle.didFinishUse()          // idle timer starts at t = 0
        clock.advance(by: 60)             // within the window
        try await lifecycle.willUse()     // new use supersedes the pending release
        clock.advance(by: 100)            // 160 s past the first didFinishUse, but reset
        lifecycle.tick()

        #expect(engine.isLoaded, "a new use before expiry must cancel the pending release")
        #expect(engine.releaseCount == 0, "the model must not be released while back in use")
    }

    /// Release is idempotent: once the idle window elapses and `tick()` releases
    /// the model, further ticks must not release it again.
    /// Stated sensitivity: drop the `idleSince = nil` reset after release in
    /// `tick()` → every later tick re-releases → releaseCount climbs past 1 → RED.
    @Test
    func releaseIsIdempotentAcrossRepeatedTicks() async throws {
        let engine = FakeSpeechEngine()
        let clock = FakeClock(start: 0)
        let lifecycle = ModelLifecycle(model: engine, keepWarmSeconds: 120, clock: clock)

        try await lifecycle.willUse()
        lifecycle.didFinishUse()
        clock.advance(by: 121)
        lifecycle.tick()  // releases once
        lifecycle.tick()  // no-op: already released
        lifecycle.tick()  // no-op

        #expect(engine.releaseCount == 1, "release must happen exactly once, not on every tick")
    }

    /// RESIDENT keep-warm (nil): the model is loaded on first use and NEVER released
    /// — didFinishUse schedules nothing, and no amount of elapsed time + ticks tears
    /// it down (speed-first default, ≤ 1 GB budget).
    /// Stated sensitivity: treat nil like a finite window (or 0) → an advanced-clock
    /// tick releases the model → still-loaded assertion fails / releaseCount > 0 → RED.
    @Test
    func residentKeepWarmNeverReleases() async throws {
        let engine = FakeSpeechEngine()
        let clock = FakeClock(start: 0)
        let lifecycle = ModelLifecycle(model: engine, keepWarmSeconds: nil, clock: clock)

        try await lifecycle.willUse()
        lifecycle.didFinishUse()
        clock.advance(by: 100_000)  // far past any finite window
        lifecycle.tick()

        #expect(engine.isLoaded, "resident (nil keep-warm) must keep the model loaded indefinitely")
        #expect(engine.releaseCount == 0, "resident (nil keep-warm) must never release")
    }

    /// EXACT boundary: `tick` releases at PRECISELY keepWarmSeconds idle — the
    /// threshold is INCLUSIVE (`>=`), so a window of 5 with the clock advanced by
    /// exactly 5 releases. This is the ONLY test that distinguishes `>=` from `>`.
    /// Stated sensitivity: mutate `tick`'s `>=` → `>` and this exact-boundary case
    /// no longer releases (5 > 5 is false) → RED — the mutant that survives every
    /// other clock test (all of which advance strictly PAST the window) dies here.
    @Test
    func releasesAtExactKeepWarmBoundary() async throws {
        let engine = FakeSpeechEngine()
        let clock = FakeClock(start: 0)
        let lifecycle = ModelLifecycle(model: engine, keepWarmSeconds: 5, clock: clock)

        try await lifecycle.willUse()
        lifecycle.didFinishUse()      // idleSince = now = 0
        clock.advance(by: 5)          // idle == keepWarm, EXACTLY
        lifecycle.tick()

        #expect(!engine.isLoaded, "tick must release at exactly keepWarmSeconds (inclusive >=)")
        #expect(engine.releaseCount == 1, "release must fire once at the inclusive boundary")
    }
}
