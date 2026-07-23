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
        // Sensitivity: drop the launch-at-login Toggle's `onChange` wiring
        // (`actions.setLaunchAtLogin(newValue)`) → this `#expect` goes RED,
        // proving the "Open at login" control is no longer wired to the app.
        #expect(general.contains("actions.setLaunchAtLogin("))

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
        // Sensitivity: delete the `.onAppear` re-seed assignment
        // `launchAtLogin = actions.launchAtLoginEnabled()` → RED. That exact form
        // appears nowhere else (`init` uses `_launchAtLogin = State(initialValue:)`),
        // so the toggle would otherwise show a stale login-item state on reopen.
        #expect(general.contains("launchAtLogin = actions.launchAtLoginEnabled()"))

        let cleanup = try Self.strippedCode("Sources/slovo/Settings/CleanupSettingsPane.swift")
        #expect(cleanup.contains(".onAppear"))
        #expect(cleanup.contains("selectedModelId = config.openRouterModel"))
        #expect(cleanup.contains("writingStyle = config.writingStyle"))
        // Key presence is NOT re-seeded here: the pane derives it live from the
        // observed availability model, so there is no snapshot to refresh.
        #expect(cleanup.contains("useSpellCheckHints = config.useSpellCheckHints"))

        let vocabulary = try Self.strippedCode("Sources/slovo/Settings/VocabularySettingsPane.swift")
        #expect(vocabulary.contains(".onAppear"))
        // "records = actions.listVocabulary()" also appears after add/delete, so
        // this counts occurrences rather than using a plain `contains` — the count
        // only reaches 3 once the `.onAppear` re-seed call is also present.
        let reseedCount = vocabulary.components(separatedBy: "records = actions.listVocabulary()").count - 1
        #expect(reseedCount >= 3)
    }

    /// Removal must be DISCOVERABLE through the native macOS editable-table idiom:
    /// a selectable list with the bottom-left ＋ / － control, where － removes the
    /// selected row(s). Swipe / Delete (`.onDelete`) alone is not findable, so this
    /// pins the visible control — a selectable list plus a selection-gated minus
    /// button wired to the removal action.
    /// Stated sensitivity (each mutation reddens exactly its `#expect`, and the
    /// three tokens appear nowhere else in the pane):
    /// - drop `List(selection: $selection)` back to a plain `List {` → RED (rows
    ///   are no longer selectable, so the ＋ / － control cannot target them).
    /// - remove the minus button's `action: removeSelected` wiring → RED (the － is
    ///   no longer wired to removal; only the hidden swipe path would remain).
    /// - drop `.disabled(selection.isEmpty)` → RED (－ would no longer be gated on a
    ///   non-empty selection, so it would offer to delete with nothing selected).
    @Test
    func vocabularyPaneExposesVisibleRemoveControl() throws {
        let vocabulary = try Self.strippedCode("Sources/slovo/Settings/VocabularySettingsPane.swift")
        #expect(vocabulary.contains("List(selection: $selection)"))
        #expect(vocabulary.contains("action: removeSelected"))
        #expect(vocabulary.contains(".disabled(selection.isEmpty)"))
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

    /// The quick-add field must become the AppKit window's first responder after
    /// joining its view hierarchy so the user can type immediately.
    /// Stated sensitivity: remove the `viewDidMoveToWindow` override, the
    /// `initialFirstResponder` assignment, or the `makeFirstResponder` call →
    /// the corresponding expectation goes RED.
    @Test
    func quickAddWindowFocusesTheTermFieldByDefault() throws {
        let source = try Self.strippedCode("Sources/slovo/Settings/VocabularyQuickAddWindow.swift")
        #expect(source.contains("InitialFocusTextField(placeholder: \"GitHub, OAuth, PostgreSQL\", text: $terms)"))
        #expect(source.contains("override func viewDidMoveToWindow()"))
        #expect(source.contains("window.initialFirstResponder = self"))
        #expect(source.contains("window.makeFirstResponder(self)"))
        #expect(!source.contains("@FocusState"))
        #expect(!source.contains(".defaultFocus("))
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
    /// actions with their key equivalents. The Settings item carries the HIG-canonical
    /// `gearshape` SF Symbol. The window-opener labels use a real ellipsis (not ASCII
    /// "..."), and the live status line renders the bare state word without a
    /// redundant "Status:" prefix. Stated sensitivity: drop the Settings item, its ","
    /// key equivalent, or its gearshape icon → RED; revert an ellipsis to "..." → the
    /// ellipsis `#expect` reddens; reintroduce the "Status:" prefix → the negative
    /// `#expect` reddens.
    @Test
    func menuBuilderRendersSettingsAndModelItems() throws {
        let builder = try Self.strippedCode("Sources/slovo/DictationMenuBuilder.swift")
        // Four config arguments force a multiline call (strict 160-char lines), so
        // the call token and the threaded trigger are asserted separately; either
        // disappearing still reddens this guard.
        #expect(builder.contains("DictationMenu.items("))
        #expect(builder.contains("trigger: trigger,"))
        #expect(builder.contains("#selector(AppDelegate.showSettingsWindow)"))
        #expect(builder.contains(#"entry.keyEquivalent = ",""#))
        #expect(builder.contains(#"NSImage(systemSymbolName: "gearshape""#),
                "the Settings item must carry the HIG-canonical gearshape symbol")
        #expect(builder.contains("target.modelMenu("))
        #expect(builder.contains(#"keyEquivalent: "q""#))
        #expect(builder.contains("Add Vocabulary…"))
        #expect(builder.contains("Settings…"))
        #expect(!builder.contains("Status: "))
    }

    /// The builder renders the no-key add-key affordance and gates the model submenu:
    /// the add-key item routes through `showCleanupSettingsForKey` (opening Settings →
    /// Cleanup), and the model submenu's `isEnabled` tracks the item's `enabled` flag
    /// (grayed when cleanup is off with a key present). Stated sensitivity: drop the
    /// add-key routing, or hardcode the model submenu's `isEnabled` in its own case →
    /// RED.
    @Test
    func menuBuilderRendersAddKeyAndGatedModelSubmenu() throws {
        let builder = try Self.strippedCode("Sources/slovo/DictationMenuBuilder.swift")
        #expect(builder.contains("Add OpenRouter Key…"))
        #expect(builder.contains("#selector(AppDelegate.showCleanupSettingsForKey)"))

        guard let modelCase = builder.range(of: "case .cleanupModel(let modelId, let enabled):"),
              let nextCase = builder.range(of: "case .", range: modelCase.upperBound..<builder.endIndex)
        else {
            Issue.record("cleanupModel case not found in builder")
            return
        }
        let modelCaseBody = builder[modelCase.upperBound..<nextCase.lowerBound]
        #expect(modelCaseBody.contains("entry.isEnabled = enabled"),
                "the model submenu must gray from the item's enabled flag, not a constant")
    }

    /// The cleanup toggle renders as an always-actionable item — the type narrowing to
    /// `isOn` removed the off-and-disabled path — with its checkmark driven by `isOn`.
    /// Stated sensitivity: reintroduce a `disabled("Clean Up Dictation")` rendering, or
    /// stop driving the state from `isOn` → RED.
    @Test
    func menuBuilderRendersCleanupToggleAsActionable() throws {
        let builder = try Self.strippedCode("Sources/slovo/DictationMenuBuilder.swift")
        guard let toggleCase = builder.range(of: "case .cleanupToggle(let isOn):"),
              let nextCase = builder.range(of: "case .", range: toggleCase.upperBound..<builder.endIndex)
        else {
            Issue.record("cleanupToggle case not found in builder")
            return
        }
        let toggleCaseBody = builder[toggleCase.upperBound..<nextCase.lowerBound]
        #expect(toggleCaseBody.contains("entry.state = isOn ? .on : .off"),
                "the toggle's checkmark must track isOn")
        #expect(!toggleCaseBody.contains(#"disabled("Clean Up Dictation")"#),
                "the toggle must be actionable — no off-and-disabled rendering path")
    }

    /// The menu's add-key affordance must actually NAVIGATE to the Cleanup pane —
    /// pinning the selector name alone is not enough: a body that opened another pane,
    /// or did nothing, would still satisfy a name-only guard yet defeat the affordance.
    /// Scope to the method body and assert it shows the Cleanup pane specifically.
    /// Stated sensitivity: switch the pane to `"general"`, or empty the body (a no-op)
    /// → RED.
    @Test
    func addKeySelectorNavigatesToTheCleanupPane() throws {
        let settings = try Self.strippedCode("Sources/slovo/Settings/AppDelegate+Settings.swift")
        guard let head = settings.range(of: "func showCleanupSettingsForKey"),
              let nextFunc = settings.range(of: "func ", range: head.upperBound..<settings.endIndex)
        else {
            Issue.record("showCleanupSettingsForKey not found")
            return
        }
        let body = settings[head.upperBound..<nextFunc.lowerBound]
        #expect(body.contains("show(pane:"),
                "the add-key affordance must open a specific Settings pane, not just any window")
        #expect(body.contains(#"PaneIdentifier("cleanup")"#),
                "the add-key affordance must open the Cleanup pane, not another")
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
