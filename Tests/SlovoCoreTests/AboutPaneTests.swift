import Testing

import SlovoCore

// The About pane and the Settings openers live in the app target, which no test
// target imports, so their wiring is pinned by scanning source. The one piece that
// is pure and importable — the version line formatter — is unit-tested directly.
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
        let builder = try AppRuntimeSourceGuardTests.code("Sources/slovo/DictationMenuBuilder.swift")
        #expect(builder.contains("\"About Slovo\""))
        #expect(builder.contains("#selector(AppDelegate.showAboutPane)"))
    }

    /// About Slovo opens Settings on About. Settings… opens the last settings pane,
    /// which the toolbar observation records through the store. The toolbar is built
    /// from the pane enum, so `AppStateTests.settingsPanesEndWithAbout` pins its order.
    /// Only the first open switches through the package's `show(pane:)`. A later open
    /// sends the toolbar item's action, as a click does. `show(pane:)` would re-show a
    /// pane an earlier crossfade left transparent, at the old pane's height.
    /// Stated sensitivity: route `showAboutPane` to the last pane, open Settings… on
    /// a fixed pane, open without switching (`show()` alone), reopen through
    /// `show(pane:)`, drop the toolbar observation or its store write, release the
    /// observation with `_ =`, or build the toolbar from a literal list → RED.
    @Test
    func settingsOpenersChooseTheirPanes() throws {
        let opener = try AppRuntimeSourceGuardTests.code("Sources/slovo/Settings/AppDelegate+Settings.swift")
        let about = try AppRuntimeSourceGuardTests.functionBody(named: "showAboutPane", in: opener)
        let settings = try AppRuntimeSourceGuardTests.functionBody(named: "showSettingsWindow", in: opener)
        #expect(about.contains(".about"), "About Slovo must open the About pane")
        #expect(settings.contains("store.state.lastSettingsPane"), "Settings… must open the last settings pane")
        #expect(
            opener.components(separatedBy: "show(pane:").count == 2
                && AppRuntimeSourceGuardTests.containsInOrder(["SettingsWindowController(panes:", "show(pane:"], in: opener),
            "only the open that builds the window may switch through show(pane:)"
        )
        #expect(
            AppRuntimeSourceGuardTests.containsInOrder(["NSApp.sendAction(", ".show()"], in: opener),
            "a later open must switch as a toolbar click does, then show without a pane"
        )
        #expect(opener.contains("observe(\\.selectedItemIdentifier"))
        #expect(opener.contains("settingsPaneObservation ="), "the observation must be retained")
        #expect(opener.contains("recordSettingsPane("))
        #expect(opener.contains("SettingsPaneID.allCases.map"))
    }

    /// The pane observes the store, so its keycaps follow a key change while it is
    /// cached, and it reads the version line's parts from the bundle.
    /// Stated sensitivity: hold the store without `@ObservedObject` (the cached pane
    /// would keep stale keycaps), read the keys from anywhere but the store, or drop
    /// either bundle-version read or the `SlovoDevBuild` read → RED.
    @Test
    func aboutPaneFollowsTheStoreAndReadsTheBundle() throws {
        let pane = try AppRuntimeSourceGuardTests.code("Sources/slovo/Settings/AboutSettingsPane.swift")
        #expect(pane.contains("@ObservedObject private var store: AppStore"))
        #expect(pane.contains("store.state.config.hotkeyConfiguration"))
        #expect(pane.contains("\"CFBundleShortVersionString\""))
        #expect(pane.contains("\"CFBundleVersion\""))
        #expect(pane.contains("\"SlovoDevBuild\""))
    }

    /// The pane renders the Glagolitic Slovo glyph "Ⱄ" (U+2C14) as its brand mark, the
    /// composed version line, and BOTH configured keys as inline keycaps — the guide
    /// states the gesture the user actually has, so neither keycap may be a literal.
    /// Stated sensitivity: change the brand glyph away from "Ⱄ" → RED (the literal is
    /// gone; a comment mention alone cannot satisfy it, as the scan strips comments);
    /// stop composing the version line via `AboutInfo.versionLine(`, drop either
    /// `Keycap(label:)` binding, or hardcode the translate keycap back to "⌃" → the
    /// matching `#expect` goes RED.
    @Test
    func aboutPaneRendersBrandGlyphVersionAndKeyKeycaps() throws {
        let view = try AppRuntimeSourceGuardTests.code("Sources/slovo/Settings/AboutSettingsPane.swift")
        #expect(view.contains("\u{2C14}"))
        #expect(view.contains("AboutInfo.versionLine("))
        #expect(view.contains("Keycap(label: hotkeys.main.displayName)"))
        #expect(view.contains("Keycap(label: hotkeys.translate.displayName)"))
        #expect(!view.contains("Keycap(label: \"\u{2303}\")"))
    }

    /// The About pane offers an Acknowledgements affordance that opens the bundled
    /// third-party notices file (THIRD-PARTY-NOTICES.md, staged into the app's
    /// Resources by the packaging scripts) in the user's default handler, through
    /// the `SettingsActions` seam.
    /// Stated sensitivity: drop the "Acknowledgements" label or the
    /// `actions.openAcknowledgements(` call from the pane, stop resolving the bundled
    /// THIRD-PARTY-NOTICES resource, or drop the `NSWorkspace.shared.open` call from
    /// the opener file → the matching `#expect` goes RED (a comment mention cannot
    /// satisfy it — the scan strips comments).
    @Test
    func aboutPaneOffersAcknowledgementsOpeningBundledNotices() throws {
        let pane = try AppRuntimeSourceGuardTests.code("Sources/slovo/Settings/AboutSettingsPane.swift")
        let opener = try AppRuntimeSourceGuardTests.code("Sources/slovo/Settings/AppDelegate+Settings.swift")
        #expect(pane.contains("\"Acknowledgements\""))
        #expect(pane.contains("actions.openAcknowledgements("))
        #expect(opener.contains("THIRD-PARTY-NOTICES"))
        #expect(opener.contains("NSWorkspace.shared.open"))
    }
}
