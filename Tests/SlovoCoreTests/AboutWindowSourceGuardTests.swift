import Foundation
import Testing

import SlovoCore

// The About window lives in the app target (not unit-importable), so its wiring is
// pinned by scanning source. The one piece that is pure and importable — the version
// line formatter — is unit-tested directly.
@Suite("About window source guards")
struct AboutWindowSourceGuardTests {
    /// The version line is composed from the bundle's marketing and build numbers.
    /// Stated sensitivity: drop the parentheses, the "Version " prefix, or swap the
    /// two components in `AboutInfo.versionLine` → the expected string mismatches →
    /// RED. This is a real unit against the importable formatter, not a source scan.
    @Test
    func versionLineComposesFromComponents() {
        #expect(AboutInfo.versionLine(marketingVersion: "0.12.0", buildNumber: "89") == "Version 0.12.0 (89)")
        #expect(AboutInfo.versionLine(marketingVersion: "1.2.3", buildNumber: "7") == "Version 1.2.3 (7)")
    }

    /// The menu builder renders the About entry and wires it to the presenter.
    /// Stated sensitivity: drop the "About Slovo" title or the
    /// `#selector(AppDelegate.showAboutWindow)` action → the matching `#expect` goes
    /// RED, proving the dropdown entry is no longer wired to the About window.
    @Test
    func menuBuilderWiresAboutItem() throws {
        let builder = try Self.strippedCode("Sources/slovo/DictationMenuBuilder.swift")
        #expect(builder.contains("\"About Slovo\""))
        #expect(builder.contains("#selector(AppDelegate.showAboutWindow)"))
    }

    /// The presenter activates the app (the `.accessory` quirk), keeps a single cached
    /// window, and reads the live version/build/trigger to pass in — the view never
    /// reaches into `Bundle` or the config store itself.
    /// Stated sensitivity: drop `NSApp.activate(ignoringOtherApps: true)` → RED (the
    /// window would open behind other apps); drop the `if aboutWindow == nil` guard or
    /// the `aboutWindow = AboutWindow()` cache assignment → RED (a repeat click would
    /// stack a new window); drop either bundle-version read or the config trigger read
    /// → RED (a hard-coded or missing value would no longer track reality).
    @Test
    func aboutPresenterActivatesCachesAndReadsLiveValues() throws {
        let presenter = try Self.strippedCode("Sources/slovo/AppDelegate+About.swift")
        #expect(presenter.contains("NSApp.activate(ignoringOtherApps: true)"))
        #expect(presenter.contains("if aboutWindow == nil"))
        #expect(presenter.contains("aboutWindow = AboutWindow()"))
        #expect(presenter.contains("ConfigStore.load(from: defaults).trigger"))
        #expect(presenter.contains(".displayName"))
        #expect(presenter.contains("\"CFBundleShortVersionString\""))
        #expect(presenter.contains("\"CFBundleVersion\""))
    }

    /// The window controller is cached and reused so a repeated open focuses the same
    /// window, and the window survives being closed (the controller outlives it).
    /// Stated sensitivity: remove the reuse-branch `contentViewController` reassignment
    /// → RED (a cached window would never refresh its trigger-dependent view); drop
    /// `isReleasedWhenClosed = false` → RED (closing once would free the cached window,
    /// so the next open would message a released object).
    @Test
    func aboutWindowReusesCachedControllerAndSurvivesClose() throws {
        let window = try Self.strippedCode("Sources/slovo/About/AboutWindow.swift")
        #expect(window.contains("windowController.window?.contentViewController = NSHostingController(rootView: view)"))
        #expect(window.contains("window.title = \"About Slovo\""))
        #expect(window.contains("window.isReleasedWhenClosed = false"))
    }

    /// The view renders the Glagolitic Slovo glyph "Ⱄ" (U+2C14) as its brand mark, the
    /// composed version line, and the trigger key as an inline keycap.
    /// Stated sensitivity: change the brand glyph away from "Ⱄ" → RED (the literal is
    /// gone; a comment mention alone cannot satisfy it, as the scan strips comments);
    /// stop composing the version line via `AboutInfo.versionLine(` or drop the
    /// `Keycap(label: triggerName)` → the matching `#expect` goes RED.
    @Test
    func aboutViewRendersBrandGlyphVersionAndTriggerKeycap() throws {
        let view = try Self.strippedCode("Sources/slovo/About/AboutView.swift")
        #expect(view.contains("\u{2C14}"))
        #expect(view.contains("AboutInfo.versionLine("))
        #expect(view.contains("Keycap(label: triggerName)"))
    }

    /// The About window offers an Acknowledgements affordance that opens the bundled
    /// third-party notices file (THIRD-PARTY-NOTICES.md, staged into the app's
    /// Resources by the packaging scripts) in the user's default handler.
    /// Stated sensitivity: drop the "Acknowledgements" label, stop resolving the
    /// bundled THIRD-PARTY-NOTICES resource, or drop the `NSWorkspace.shared.open`
    /// call → the matching `#expect` goes RED (a comment mention cannot satisfy it —
    /// the scan strips comments). RED today: the affordance does not yet exist.
    @Test
    func aboutViewOffersAcknowledgementsOpeningBundledNotices() throws {
        let view = try Self.strippedCode("Sources/slovo/About/AboutView.swift")
        #expect(view.contains("\"Acknowledgements\""))
        #expect(view.contains("THIRD-PARTY-NOTICES"))
        #expect(view.contains("NSWorkspace.shared.open"))
    }

    private static func code(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot.appending(path: relativePath), encoding: .utf8)
    }

    /// Source with comments stripped, so a token that appears only inside a comment
    /// (a doc-comment naming a selector, or a `//` note quoting the glyph) neither
    /// satisfies a positive assert nor trips a negative one.
    private static func strippedCode(_ relativePath: String) throws -> String {
        strippingComments(from: try code(relativePath))
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

    private static var packageRoot: URL {
        let testFile = URL(fileURLWithPath: "\(#filePath)")
        return testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
