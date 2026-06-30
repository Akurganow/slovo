import Foundation
import Testing

import LoquiCore
import LoquiTestSupport

// Epic 05 — AC-3 (idle-release after keepWarm) and AC-4 (immediate release at
// keepWarm == 0).
//
// Contract under test (implementer builds the PRODUCT `ModelLifecycle` +
// `ModelLoading`/`Clock` seams in `Sources/LoquiCore/ASR/ModelLifecycle.swift`
// per plan §4; CURRENTLY supplied by the WRONG-ON-PURPOSE
// `_RedScaffold_AsrBakeoff.swift` stub that NEVER releases — so both tests RED).
@Suite("Epic 05 AC-3/AC-4 model lifecycle")
struct ModelLifecycleTests {

    /// AC-3: after `didFinishUse()`, advancing the clock PAST keepWarmSeconds and
    /// calling `tick()` releases the model; within the window it stays loaded.
    /// Stated sensitivity: never release → the model stays loaded past the window
    /// → RED. (The scaffold never releases → RED now.)
    @Test
    func releasesAfterIdleExceedsKeepWarm() async throws {
        let model = FakeModel()
        let clock = FakeClock(start: 0)
        let lifecycle = ModelLifecycle(model: model, keepWarmSeconds: 120, clock: clock)

        try await lifecycle.willUse()
        #expect(model.isLoaded, "willUse must load the model")

        lifecycle.didFinishUse()

        // Within the keep-warm window: still loaded.
        clock.advance(by: 60)
        lifecycle.tick()
        #expect(model.isLoaded, "model must stay loaded within the 120 s keep-warm window")

        // Past the window: released.
        clock.advance(by: 61)  // total idle 121 s > 120
        lifecycle.tick()
        #expect(!model.isLoaded, "model must be released once idle exceeds keepWarmSeconds")
        #expect(model.releaseCount >= 1, "release() must have been called")
    }

    /// AC-4: with keepWarmSeconds == 0, `didFinishUse()` releases immediately (no
    /// tick needed).
    /// Stated sensitivity: keep warm despite keepWarm == 0 → still loaded → RED.
    /// (The scaffold never releases → RED now.)
    @Test
    func releasesImmediatelyWhenKeepWarmIsZero() async throws {
        let model = FakeModel()
        let clock = FakeClock(start: 0)
        let lifecycle = ModelLifecycle(model: model, keepWarmSeconds: 0, clock: clock)

        try await lifecycle.willUse()
        #expect(model.isLoaded, "willUse must load the model")

        lifecycle.didFinishUse()
        #expect(!model.isLoaded, "keepWarmSeconds == 0 must release immediately on didFinishUse()")
    }
}
