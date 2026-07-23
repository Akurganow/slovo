import Foundation
import Testing

// The observation invariant (spec D1): the Settings pane is the one former
// snapshot-mirror of cleanup availability, so it must render the app-layer
// observable model the push funnel writes — never hold its own snapshot or
// re-fetch — and the funnel must stay that model's only writer, or the pane
// could show a value no other surface agrees with.
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
        // nor an attribute-on-its-own-line declaration slips past. \b keeps the
        // model reference legal: `CleanupAvailabilityModel` has no word boundary
        // before "Model", so it cannot trip a check aimed at the VALUE type.
        let snapshotPattern = try NSRegularExpression(pattern: #"@State[^\n]*\n?[^\n]*CleanupAvailability\b"#)
        let range = NSRange(pane.startIndex..<pane.endIndex, in: pane)
        #expect(snapshotPattern.numberOfMatches(in: pane, range: range) == 0, "the pane must hold no availability @State snapshot")
    }

    /// Stated sensitivity: stop consuming the observed model (render from a local
    /// copy, or poll the seam again) → the seam or read assert reddens; hold the
    /// model as a plain reference without `@ObservedObject` (compiles, but the
    /// pane silently stops repainting on funnel writes) → the subscription
    /// assert reddens.
    @Test
    func paneRendersFromTheObservedModel() throws {
        let pane = try Self.strippedCode("Sources/slovo/Settings/CleanupSettingsPane.swift")
        #expect(pane.contains("actions.cleanupAvailabilityModel"), "the pane must reach the model through the SettingsActions seam")
        #expect(pane.contains("@ObservedObject private var availabilityModel: CleanupAvailabilityModel"),
                "the pane must SUBSCRIBE to the model — a plain reference never repaints")
        #expect(pane.contains("availabilityModel.availability"), "the pane must read availability off the observed model")
    }

    /// Stated sensitivity: delete the funnel's model write → the count assert
    /// reddens (0); add a second writer anywhere in the app target → the count
    /// assert reddens (2); move the single write out of the funnel → the funnel-body
    /// assert reddens; move the write INSIDE the orchestrator `Task` hop (past the
    /// await — the pane then lags the mutation by a runloop turn or more) → the
    /// order assert reddens. Either way the invariant breaks visibly.
    @Test
    func pushFunnelIsTheOnlyModelWriter() throws {
        let writeToken = "cleanupAvailabilityModel.update("
        let writeCount = try Self.appTargetSources()
            .map { $0.contents.components(separatedBy: writeToken).count - 1 }
            .reduce(0, +)
        #expect(writeCount == 1, "exactly one model write site may exist; found \(writeCount)")

        let delegate = try Self.strippedCode("Sources/slovo/AppDelegate.swift")
        guard let funnel = delegate.range(of: "func pushEffectiveCleanupConfig") else {
            Issue.record("pushEffectiveCleanupConfig not found")
            return
        }
        // Scope the scan to the funnel body — from its declaration to the next
        // `func` declaration — so a write parked in a neighboring function
        // cannot satisfy the location assert.
        let tail = delegate[funnel.upperBound...]
        let funnelBody = tail.range(of: "\n    func ").map { tail[..<$0.lowerBound] } ?? tail
        #expect(funnelBody.contains(writeToken), "the single model write must live inside the push funnel")
        // Same-turn publish is positional: the write must PRECEDE the async
        // orchestrator hop, or observers see it a runloop turn late (spec D1).
        guard let write = funnelBody.range(of: writeToken), let hop = funnelBody.range(of: "Task {") else {
            Issue.record("the funnel's model write or orchestrator hop not found")
            return
        }
        #expect(write.lowerBound < hop.lowerBound, "the model write must come before the orchestrator Task hop")
    }

    /// Stated sensitivity: refactor AppDelegate's stored `lazy var` model into a
    /// COMPUTED property → RED. The computed form compiles, but every consumer
    /// then gets a fresh throwaway instance: the funnel writes one nobody holds
    /// and the pane silently never repaints — the snapshot bug reborn through
    /// identity. This pins the stored-instance declaration lexically; true
    /// instance-identity behavior stays runbook-backed, app-layer code being
    /// unit-unimportable by repo convention.
    @Test
    func appDelegateStoresOneSharedModelInstance() throws {
        let delegate = try Self.strippedCode("Sources/slovo/AppDelegate.swift")
        #expect(delegate.contains("lazy var cleanupAvailabilityModel = CleanupAvailabilityModel("),
                "the model must be a STORED property — a computed form mints a throwaway instance per access")
    }

    private static func appTargetSources() throws -> [(relativePath: String, contents: String)] {
        let root = packageRoot.appending(path: "Sources/slovo", directoryHint: .isDirectory).path
        return try FileManager.default.subpathsOfDirectory(atPath: root)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
            .map { (relativePath: "Sources/slovo/\($0)", contents: try strippedCode("Sources/slovo/\($0)")) }
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
