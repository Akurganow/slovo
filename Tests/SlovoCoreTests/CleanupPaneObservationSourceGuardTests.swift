import Foundation
import Testing

// The observation invariant: every reader of the app's store gets the same store.
// No test target depends on the `slovo` executable, so this guard reads its source.
@Suite("Cleanup pane observation source guard")
struct CleanupPaneObservationSourceGuardTests {
    /// Stated sensitivity: turn AppDelegate's stored `let store` into a COMPUTED
    /// property → RED. The computed form compiles, but every reader then gets a
    /// fresh store: writers update one nobody observes, and the pane never repaints.
    /// This pins the stored declaration lexically.
    @Test
    func appDelegateStoresOneSharedStore() throws {
        let delegate = try SourceText.code("Sources/slovo/AppDelegate.swift")
        #expect(delegate.contains("let store: AppStore"),
                "the store must be a STORED property — a computed form mints a store per access")
    }
}
