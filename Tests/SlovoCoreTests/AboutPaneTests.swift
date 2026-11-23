import Testing

import SlovoCore

// The About menu row is tested in `Tests/SlovoAppTests/DictationMenuRowTests.swift`.
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
}
