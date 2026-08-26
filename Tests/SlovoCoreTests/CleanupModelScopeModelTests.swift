import Synchronization
import Testing
import SlovoCore

@Suite("CleanupModelScopeModel")
@MainActor
struct CleanupModelScopeModelTests {
    // Same invariant as CleanupAvailabilityModel: synchronous update, observers
    // see the new value in the same runloop turn.
    @Test
    func updateIsSynchronous() {
        let model = CleanupModelScopeModel(scope: .unknown)
        model.update(.known(["a/b"]))
        #expect(model.scope == .known(["a/b"]))
    }

    /// Sensitivity: drop `@Published` from `scope` — the value still updates but
    /// `objectWillChange` never fires, so the pane's subscription silently dies → RED.
    @Test
    func updateFiresTheChangeNotificationSynchronously() {
        let model = CleanupModelScopeModel(scope: .unknown)
        // A Mutex flag, not an actor: the notification is delivered synchronously
        // at mutation time, and the assertion must read it without introducing a
        // suspension point.
        let didNotify = Mutex(false)
        let subscription = model.objectWillChange.sink { didNotify.withLock { $0 = true } }
        model.update(.known(["a/b"]))
        #expect(didNotify.withLock { $0 }, "the mutation must notify observers before update() returns")
        #expect(model.scope == .known(["a/b"]))
        subscription.cancel()
    }
}
