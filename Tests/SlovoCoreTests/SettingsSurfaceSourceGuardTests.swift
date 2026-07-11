import Foundation
import Testing

// App-target Settings surfaces are not unit-importable, so this guard scans their
// source: each pane must drive the SettingsActions seam, the Phase-3 checkbox must
// NOT exist yet, and the panes must be package-agnostic SwiftUI.
@Suite("Settings surface source guards")
struct SettingsSurfaceSourceGuardTests {
    /// Stated sensitivity: drop a pane's call to its setter (e.g. delete
    /// `actions.setTrigger`) → the corresponding `#expect` goes RED, proving the
    /// control is no longer wired to the app. Read over comment-stripped source so a
    /// setter name that survives only inside a `//` comment cannot satisfy the assert.
    @Test
    func panesDriveTheSettingsActionsSeam() throws {
        let general = try Self.strippedCode("Sources/slovo/Settings/GeneralSettingsPane.swift")
        #expect(general.contains("HotkeyTrigger.allCases"))
        #expect(general.contains("option.displayName"))
        #expect(general.contains("actions.setTrigger("))
        #expect(general.contains("actions.setRecognitionLanguage("))

        let cleanup = try Self.strippedCode("Sources/slovo/Settings/CleanupSettingsPane.swift")
        #expect(cleanup.contains("CleanupModelCatalog.options"))
        #expect(cleanup.contains("actions.setCleanupModel("))
        #expect(cleanup.contains("actions.setWritingStyle("))
        #expect(cleanup.contains("actions.saveOpenRouterKey("))

        let vocabulary = try Self.strippedCode("Sources/slovo/Settings/VocabularySettingsPane.swift")
        #expect(vocabulary.contains("actions.listVocabulary()"))
        #expect(vocabulary.contains("actions.addVocabulary("))
        #expect(vocabulary.contains("actions.removeVocabulary("))
    }

    /// Windows are cached and reopened, not recreated, so a pane's `@State` must be
    /// re-seeded from the live config on every reappearance — otherwise a value
    /// edited elsewhere (the dropdown, or a sibling pane) shows stale until relaunch.
    /// Stated sensitivity: delete a pane's `.onAppear` re-seed assignment (e.g.
    /// `trigger = config.trigger` in `GeneralSettingsPane`) → the corresponding
    /// `#expect` goes RED, since that exact assignment form appears nowhere else in
    /// the pane (`init` uses the distinct `_trigger = State(initialValue:)` form).
    @Test
    func panesReseedFromCurrentConfigOnAppear() throws {
        let general = try Self.strippedCode("Sources/slovo/Settings/GeneralSettingsPane.swift")
        #expect(general.contains(".onAppear"))
        #expect(general.contains("trigger = config.trigger"))
        #expect(general.contains("language = config.language"))

        let cleanup = try Self.strippedCode("Sources/slovo/Settings/CleanupSettingsPane.swift")
        #expect(cleanup.contains(".onAppear"))
        #expect(cleanup.contains("selectedModelId = config.openRouterModel"))
        #expect(cleanup.contains("writingStyle = config.writingStyle"))
        #expect(cleanup.contains("hasSavedKey = actions.hasOpenRouterKey()"))
        #expect(cleanup.contains("useSpellCheckHints = config.useSpellCheckHints"))

        let vocabulary = try Self.strippedCode("Sources/slovo/Settings/VocabularySettingsPane.swift")
        #expect(vocabulary.contains(".onAppear"))
        // "records = actions.listVocabulary()" also appears after add/delete, so
        // this counts occurrences rather than using a plain `contains` — the count
        // only reaches 3 once the `.onAppear` re-seed call is also present.
        let reseedCount = vocabulary.components(separatedBy: "records = actions.listVocabulary()").count - 1
        #expect(reseedCount >= 3)
    }

    /// The quick-add window's controller is cached, but the view it hosts must be
    /// rebuilt fresh on every `show()` — otherwise text left over from a cancelled
    /// add would still be in the field on reopen.
    /// Stated sensitivity: move view construction back inside
    /// `if windowController == nil { ... }` (so a cached window reuses its old
    /// view) → this `#expect` goes RED, since the reused-branch's
    /// `contentViewController` reassignment is what proves a fresh view replaces
    /// the stale one.
    @Test
    func quickAddWindowRebuildsViewOnEveryShow() throws {
        let source = try Self.strippedCode("Sources/slovo/Settings/VocabularyQuickAddWindow.swift")
        #expect(source.contains("windowController.window?.contentViewController = NSHostingController(rootView: view)"))
    }

    /// Phase 3 landed: the Cleanup pane now hosts the spell-check hints toggle at the
    /// former extension point (inverts the retired
    /// `cleanupPaneLeavesPhase3ExtensionPointUnimplemented`).
    /// Stated sensitivity: removing the `Toggle("Use system spell-check hints", …)`
    /// from the pane turns this red.
    @Test
    func cleanupPaneHostsSpellCheckHintsToggle() throws {
        let cleanup = try Self.strippedCode("Sources/slovo/Settings/CleanupSettingsPane.swift")

        #expect(cleanup.contains("Use system spell-check hints"))
    }

    /// The window presenter activates the app before showing (the `.accessory`
    /// quirk) and avoids the broken SwiftUI Settings route.
    /// Stated sensitivity: drop `NSApp.activate(ignoringOtherApps: true)` → RED
    /// (the window would open behind other apps); use `openSettings`/`SettingsLink`
    /// → the forbidden-route `#expect` goes RED.
    @Test
    func settingsWindowActivatesBeforeShowing() throws {
        // Comment-stripped: the presenter's doc-comment names `openSettings` /
        // `SettingsLink` to explain why they are avoided, so a raw read would
        // false-trip the two negative asserts below.
        let presenter = try Self.strippedCode("Sources/slovo/Settings/AppDelegate+Settings.swift")
        #expect(presenter.contains("NSApp.activate(ignoringOtherApps: true)"))
        #expect(!presenter.contains("SettingsLink"))
        #expect(!presenter.contains("openSettings"))
    }

    /// The menu builder renders the model items and wires the Settings + quit
    /// actions with their key equivalents. Stated sensitivity: drop the Settings
    /// item or its "," key equivalent → RED.
    @Test
    func menuBuilderRendersSettingsAndModelItems() throws {
        let builder = try Self.strippedCode("Sources/slovo/DictationMenuBuilder.swift")
        #expect(builder.contains("DictationMenu.items(trigger:"))
        #expect(builder.contains("#selector(AppDelegate.showSettingsWindow)"))
        #expect(builder.contains(#"entry.keyEquivalent = ",""#))
        #expect(builder.contains("target.modelMenu("))
        #expect(builder.contains(#"keyEquivalent: "q""#))
    }

    /// `makeMenu` must pass the REAL current config to the builder. Without this,
    /// after the builder move nothing pins that the dropdown reflects the user's
    /// settings. Stated sensitivity: hardcode `trigger: .fn` or `selectedModelId: ""`
    /// in `makeMenu` → the hint line and model checkmark stop tracking config → RED.
    @Test
    func makeMenuFeedsBuilderTheRealConfig() throws {
        let delegate = try Self.strippedCode("Sources/slovo/AppDelegate.swift")
        #expect(delegate.contains("trigger: config.trigger"))
        #expect(delegate.contains("selectedModelId: config.openRouterModel"))
    }

    private static func code(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot.appending(path: relativePath), encoding: .utf8)
    }

    /// Source with comments stripped, so a token that appears only inside a comment
    /// (a doc-comment mentioning `openSettings`, or a `//` note naming a setter)
    /// neither satisfies a positive assert nor trips a negative one.
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
