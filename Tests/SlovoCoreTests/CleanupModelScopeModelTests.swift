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
}
