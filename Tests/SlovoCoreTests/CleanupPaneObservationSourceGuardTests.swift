import Foundation
import Testing

// The observation invariant (spec D1): the Cleanup pane renders the app's store,
// never its own snapshot or a re-fetch, so it cannot show a value no other
// surface agrees with.
@Suite("Cleanup pane observation source guard")
struct CleanupPaneObservationSourceGuardTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Stated sensitivity: re-introduce an availability `@State` snapshot in the
    /// pane — explicitly typed, type-INFERRED (`= CleanupAvailability.…`, no
    /// colon), or with `@State` on a line of its own above the declaration →
    /// the regex assert reddens; re-introduce any manual re-fetch site
    /// (init seed, `.onAppear` re-seed, post-toggle or post-save refresh via
    /// `cleanupAvailability()`) → the contains assert reddens.
    @Test
    func paneHoldsNoAvailabilitySnapshot() throws {
        let pane = try Self.strippedCode("Sources/slovo/Settings/CleanupSettingsPane.swift")
        #expect(!pane.contains("cleanupAvailability()"), "the pane must never re-fetch availability manually")
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
        let pane = try Self.strippedCode("Sources/slovo/Settings/CleanupSettingsPane.swift")
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
        let delegate = try Self.strippedCode("Sources/slovo/AppDelegate.swift")
        #expect(delegate.contains("let store: AppStore"),
                "the store must be a STORED property — a computed form mints a store per access")
    }

    /// Source with comments stripped, so a token surviving only in a comment can
    /// neither satisfy a positive assert nor trip a negative one. Mirrors
    /// AppRuntimeSourceGuardTestsSupport.strippingComments.
    private static func strippedCode(_ relativePath: String) throws -> String {
        strippingComments(from: try String(
            contentsOf: packageRoot.appending(path: relativePath),
            encoding: .utf8
        ))
    }

    private static func strippingComments(from source: String) -> String {
        var output = ""
        var index = source.startIndex
        var inLineComment = false, inBlockComment = false, inString = false
        while index < source.endIndex {
            let character = source[index]
            let nextIndex = source.index(after: index)
            let next = nextIndex < source.endIndex ? source[nextIndex] : "\0"
            if inLineComment {
                if character == "\n" { inLineComment = false; output.append(character) }
            } else if inBlockComment {
                if character == "*" && next == "/" { inBlockComment = false; index = nextIndex }
            } else if inString {
                output.append(character)
                if character == "\"" { inString = false }
            } else if character == "/" && next == "/" {
                inLineComment = true; index = nextIndex
            } else if character == "/" && next == "*" {
                inBlockComment = true; index = nextIndex
            } else {
                output.append(character)
                if character == "\"" { inString = true }
            }
            index = source.index(after: index)
        }
        return output
    }
}
