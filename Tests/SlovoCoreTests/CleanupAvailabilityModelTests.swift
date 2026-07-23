import Synchronization
import Testing

import SlovoCore

// The observable holder behind the observation invariant (spec D1): a funnel
// write must be visible to observers synchronously — same runloop turn, no
// scheduling hop — which is what makes the pane's live reflection testable
// without sleeps.
@Suite("Cleanup availability model")
struct CleanupAvailabilityModelTests {
    /// Stated sensitivity: defer the write inside `update` (e.g. hop through a
    /// Task) → the read on the next line still sees the old value → RED.
    @Test
    @MainActor
    func updateIsVisibleSynchronously() {
        let model = CleanupAvailabilityModel(availability: .offNoKey)
        #expect(model.availability == .offNoKey, "init must seed the published value")
        model.update(.on)
        #expect(model.availability == .on)
        model.update(.offByChoice)
        #expect(model.availability == .offByChoice)
    }

    /// Stated sensitivity: break the change notification — drop `@Published` from
    /// the property (or defer the write) — and `objectWillChange` never fires, so
    /// a pane rendering the model would silently stop repainting → RED.
    @Test
    @MainActor
    func updateFiresTheChangeNotificationSynchronously() {
        let model = CleanupAvailabilityModel(availability: .offByChoice)
        // A Mutex flag, not an actor: the notification is delivered synchronously
        // at mutation time, and the assertion must read it without introducing a
        // suspension point.
        let didNotify = Mutex(false)
        let subscription = model.objectWillChange.sink { didNotify.withLock { $0 = true } }
        model.update(.on)
        #expect(didNotify.withLock { $0 }, "the mutation must notify observers before update() returns")
        #expect(model.availability == .on)
        subscription.cancel()
    }
}
