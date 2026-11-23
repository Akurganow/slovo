import Testing

import SlovoCore

// No test target depends on the `slovo` executable, so the About menu entry is pinned by
// scanning source. The one piece that is pure and importable — the version line
// formatter — is unit-tested directly.
@Suite("About pane")
struct AboutPaneTests {
    /// The version line is composed from the bundle's marketing and build numbers,
    /// and a dev build appends the space-separated Glagolitic capital Dobro "Ⰴ"
    /// (U+2C04) while a release line stays byte-identical to the marker-free form.
    /// Stated sensitivity: drop the parentheses, the "Version " prefix, or swap the
    /// two components → RED; change or drop the Dobro suffix, or leak the marker
    /// into the release branch → an exact-equality `#expect` mismatches → RED. This
    /// is a real unit against the importable formatter, not a source scan.
    @Test
    func versionLineComposesForReleaseAndDevBuilds() {
        #expect(
            AboutInfo.versionLine(marketingVersion: "0.12.0", buildNumber: "89", isDevBuild: false)
                == "Version 0.12.0 (89)"
        )
        #expect(
            AboutInfo.versionLine(marketingVersion: "0.12.0", buildNumber: "89", isDevBuild: true)
                == "Version 0.12.0 (89) \u{2C04}"
        )
        #expect(
            AboutInfo.versionLine(marketingVersion: "1.2.3", buildNumber: "7", isDevBuild: false)
                == "Version 1.2.3 (7)"
        )
        #expect(
            AboutInfo.versionLine(marketingVersion: "0.19.0-ci.777", buildNumber: "777", isDevBuild: false)
                == "Version 0.19.0-ci.777 (777)"
        )
    }

    /// The menu builder renders the About entry and wires it to the About opener.
    /// Stated sensitivity: drop the "About Slovo" title or the
    /// `#selector(AppDelegate.showAboutPane)` action → the matching `#expect` goes
    /// RED, proving the dropdown entry no longer opens the About pane.
    @Test
    func menuBuilderWiresAboutItem() throws {
        let builder = try SourceText.code("Sources/slovo/DictationMenuBuilder.swift")
        #expect(builder.contains("\"About Slovo\""))
        #expect(builder.contains("#selector(AppDelegate.showAboutPane)"))
    }
}
