import Foundation
import Testing

// The observation invariant: the Cleanup pane renders the app's store, never its own
// snapshot or a re-fetch, so it cannot show a value no other surface agrees with.
// No test target depends on the `slovo` executable, so these guards read its source.
@Suite("Cleanup pane observation source guard")
struct CleanupPaneObservationSourceGuardTests {
    /// Stated sensitivity: re-introduce an availability `@State` snapshot in the
    /// pane — explicitly typed, type-INFERRED (`= CleanupAvailability.…`, no
    /// colon), or with `@State` on a line of its own above the declaration → RED.
    @Test
    func paneHoldsNoAvailabilitySnapshot() throws {
        let pane = try SourceText.code("Sources/slovo/Settings/CleanupSettingsPane.swift")
        // A two-line window after every `@State`, so neither a type-inferred seed
        // nor an attribute-on-its-own-line declaration slips past. `\b` ends the
        // match at the value type's name, so a longer identifier that starts with
        // it cannot trip the check.
        let snapshotPattern = try NSRegularExpression(pattern: #"@State[^\n]*\n?[^\n]*CleanupAvailability\b"#)
        let range = NSRange(pane.startIndex..<pane.endIndex, in: pane)
        #expect(snapshotPattern.numberOfMatches(in: pane, range: range) == 0, "the pane must hold no availability @State snapshot")
    }

    /// Stated sensitivity: stop consuming the store (render from a local copy, or
    /// poll the seam again) → the seam or read assert reddens; hold the store as a
    /// plain reference without `@ObservedObject` (compiles, but the pane silently
    /// stops repainting on store writes) → the subscription assert reddens.
    @Test
    func paneRendersFromTheObservedModel() throws {
        let pane = try SourceText.code("Sources/slovo/Settings/CleanupSettingsPane.swift")
        #expect(pane.contains("actions.store"), "the pane must reach the store through the SettingsActions seam")
        #expect(pane.contains("@ObservedObject private var store: AppStore"),
                "the pane must SUBSCRIBE to the store — a plain reference never repaints")
        #expect(pane.contains("store.state.cleanupAvailability"), "the pane must read availability off the observed store")
    }

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
