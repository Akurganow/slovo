import Foundation
import Testing

// App-target Settings surfaces are not unit-importable, so this guard scans their
// source: each pane must drive the SettingsActions seam and stay package-agnostic
// SwiftUI.
@Suite("Settings surface source guards")
struct SettingsSurfaceSourceGuardTests {
    /// Each pane's `Config` controls bind the store through `store.binding(_:)`, and
    /// the actions with effects outside the store go through the SettingsActions
    /// seam. Read over comment-stripped source so a name that survives only inside a
    /// `//` comment cannot satisfy the assert.
    /// Stated sensitivity: replace a control's `store.binding(\.field)` with a local
    /// `@State` or a constant, or drop a surviving action call (e.g.
    /// `actions.setLaunchAtLogin(`) → the corresponding `#expect` goes RED.
    @Test
    func panesWriteThroughStoreBindingsAndActions() throws {
        let general = try Self.strippedCode("Sources/slovo/Settings/GeneralSettingsPane.swift")
        #expect(general.contains("HotkeyTrigger.allCases"))
        #expect(general.contains("option.displayName"))
        for field in [
            "trigger", "translateTrigger", "translateKeyIsAdditional", "language",
            "usesVocabularyBias", "playsDictationSoundCues", "automaticallyInstallsUpdates",
        ] {
            #expect(general.contains("store.binding(\\.\(field))"), "General must bind \(field) to the store")
        }
        #expect(general.contains("actions.setLaunchAtLogin("))

        let cleanup = try Self.strippedCode("Sources/slovo/Settings/CleanupSettingsPane.swift")
        // The single-derivation invariant (K6): the pane renders the state's
        // selector and does NOT derive inline (displayName lookups in captions remain).
        #expect(cleanup.contains("store.state.cleanupModelSelection"))
        #expect(!cleanup.contains("CleanupModelSelection.derive("))
        for field in ["writingStyle", "translationTargetLanguage", "useSpellCheckHints"] {
            #expect(cleanup.contains("store.binding(\\.\(field))"), "Cleanup must bind \(field) to the store")
        }
        #expect(cleanup.contains("$0.config.openRouterModel = trimmedCustomModelId"))
        #expect(cleanup.contains("actions.saveOpenRouterKey("))
        // K3 seed-guard, source form (no test target links Sources/slovo): the pane
        // has no selection @State to re-seed, and the Picker binding's
        // user-interaction set writes the preference.
        // Sensitivity: restore the selectedModelId re-seed → onChange wiring → RED.
        #expect(!cleanup.contains("selectedModelId"))
        #expect(!cleanup.contains("State(initialValue: config.openRouterModel)"))
        #expect(cleanup.contains("set: { newValue in store.update { $0.config.openRouterModel = newValue } }"))
        // The pinned caption copy (spec K2 rev 3) — the substitution caption is
        // pinned as its FULL code literal (a bare prefix would be satisfied by the
        // custom warning alone; v3-verification L1):
        #expect(cleanup.contains(
            #"Your key can't use \(CleanupModelCatalog.displayName(for: preferred)) — using \(CleanupModelCatalog.displayName(for: effective))."#))
        #expect(cleanup.contains(#"Your key can't use this model. Dictations may insert the raw transcript."#))

        let vocabulary = try Self.strippedCode("Sources/slovo/Settings/VocabularySettingsPane.swift")
        #expect(vocabulary.contains("store.state.vocabulary"))
        #expect(vocabulary.contains("actions.addVocabulary("))
        #expect(vocabulary.contains("actions.removeVocabulary("))
    }

    /// The login item is the one value a pane still snapshots: System Settings can
    /// change it while the window is cached, so the General pane re-reads it on
    /// every reappearance. Every `Config` value binds the store instead.
    /// Stated sensitivity: delete the `.onAppear` re-seed
    /// `launchAtLogin = actions.launchAtLoginEnabled()` → RED. That exact form appears
    /// nowhere else (`init` uses `_launchAtLogin = State(initialValue:)`).
    @Test
    func generalPaneReseedsLaunchAtLoginOnAppear() throws {
        let general = try Self.strippedCode("Sources/slovo/Settings/GeneralSettingsPane.swift")
        let onAppear = try Self.blockBody(after: ".onAppear", in: general)
        #expect(onAppear.contains("launchAtLogin = actions.launchAtLoginEnabled()"))
    }

    /// The two key pickers cannot be pointed at the same key BY CONSTRUCTION: each
    /// renders the other's key, read from the store, as an unselectable row —
    /// disabled, not hidden, so the user sees why. The store's validation stays the
    /// authoritative check (`AppStoreTests.invalidConfigIsRefusedWhole`).
    /// Each assertion is scoped to its OWN picker, so swapping the two conditions
    /// cannot pass.
    /// Stated sensitivity: drop either `.selectionDisabled(…)`, or SWAP the two
    /// conditions between the pickers → the matching `#expect` reddens; filter the
    /// pool instead (hiding the row rather than disabling it) → RED.
    @Test
    func keyPickersDisableEachOthersSelection() throws {
        let general = try Self.strippedCode("Sources/slovo/Settings/GeneralSettingsPane.swift")
        let mainPicker = try Self.blockBody(
            after: #"Picker("Push-to-talk key", selection: store.binding(\.trigger))"#, in: general
        )
        #expect(mainPicker.contains(".selectionDisabled(option == store.state.config.translateTrigger)"),
                "the push-to-talk picker must disable the key the TRANSLATE role holds")
        let translatePicker = try Self.blockBody(
            after: #"Picker("Translate key", selection: store.binding(\.translateTrigger))"#, in: general
        )
        #expect(translatePicker.contains(".selectionDisabled(option == store.state.config.trigger)"),
                "the translate picker must disable the key the MAIN role holds")
    }

    /// The translate row reads `<main key> + [dropdown]` while the key is additional
    /// and collapses to the bare dropdown when it is not. The prefix reads the same
    /// store value the main picker binds, and the selected translate key appears
    /// only inside the dropdown.
    /// Stated sensitivity: hardcode the prefix ("fn +"), drop the
    /// `translateKeyIsAdditional` condition, or restate the translate key beside the
    /// dropdown → the matching `#expect` reddens.
    @Test
    func translateRowPrefixesTheMainKeyOnlyWhileAdditional() throws {
        let general = try Self.strippedCode("Sources/slovo/Settings/GeneralSettingsPane.swift")
        let row = try Self.blockBody(after: #"LabeledContent("Translate key")"#, in: general)
        #expect(row.contains("if store.state.config.translateKeyIsAdditional {"))
        #expect(row.contains(#"Text("\(store.state.config.trigger.displayName) +")"#))
        #expect(!row.contains("translateTrigger.displayName"),
                "the selected translate key must appear only inside the dropdown, never duplicated as text")
        #expect(general.contains(#"Toggle(isOn: store.binding(\.translateKeyIsAdditional))"#))
        #expect(general.contains(#"Text("Use as additional key")"#))
    }

    /// The Cleanup pane's translate caption must name the REAL gesture: it derives
    /// from the keys in the store, which the General pane edits, and it branches on
    /// the shared gesture value, never on prose.
    /// Stated sensitivity: restore the hardcoded "Used when you hold Control while
    /// dictating." → the negative `#expect` reddens; read the keys from anywhere but
    /// the store → RED; SWAP the two branches' wording → the pairing `#expect`s
    /// redden, because each case is pinned TOGETHER WITH the sentence it produces.
    @Test
    func cleanupPaneCaptionNamesTheConfiguredTranslateGesture() throws {
        let cleanup = try Self.strippedCode("Sources/slovo/Settings/CleanupSettingsPane.swift")
        #expect(!cleanup.contains("hold Control while dictating"),
                "the caption must not name a key the user may not have bound")
        let caption = try Self.blockBody(after: "var translateCaption", in: cleanup)
        #expect(caption.contains("store.state.config.hotkeyConfiguration"))
        #expect(caption.contains("hotkeys.translate.displayName"))
        #expect(caption.contains(#"case .additional: return "Used when you add"#),
                "an additional key is ADDED to a dictation already under way")
        #expect(caption.contains(#"case .standalone: return "Used when you dictate with"#),
                "a standalone key's own hold IS the dictation")
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
        // the call token and the threaded key configuration are asserted separately;
        // either disappearing still reddens this guard.
        #expect(builder.contains("DictationMenu.items("))
        #expect(builder.contains("hotkeys: hotkeys,"))
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
    /// the add-key item routes through `showAddOpenRouterKeyWindow` (opening the
    /// dedicated key window), and the model submenu's `isEnabled` tracks the item's
    /// `enabled` flag (grayed when cleanup is off with a key present). Stated
    /// sensitivity: drop the add-key routing, or hardcode the model submenu's
    /// `isEnabled` in its own case → RED.
    @Test
    func menuBuilderRendersAddKeyAndGatedModelSubmenu() throws {
        let builder = try Self.strippedCode("Sources/slovo/DictationMenuBuilder.swift")
        #expect(builder.contains("Add OpenRouter Key…"))
        #expect(builder.contains("#selector(AppDelegate.showAddOpenRouterKeyWindow)"))

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

    /// The renderer paints the translate hint as its own disabled line, and creates the
    /// persistent fn-conflict row from the model's shared fn rule — the row must exist
    /// whenever fn is bound in EITHER role, or the open-time re-sync has nothing to
    /// reveal for a translate key on fn.
    /// Stated sensitivity: empty the hint case (`case .translateHint: break` compiles
    /// and silently drops the row) or render it actionable → RED; narrow the row's
    /// creation back to `hotkeys.main == .fn` → RED.
    @Test
    func menuBuilderRendersTheTranslateHintAndTheFnRowForEitherRole() throws {
        let builder = try Self.strippedCode("Sources/slovo/DictationMenuBuilder.swift")
        // Asserted before the scoped check below, whose guard-else would otherwise
        // skip it whenever the hint case is the thing that broke.
        #expect(builder.contains("if hotkeys.usesFnKey {"),
                "the persistent fn-conflict row must follow the configuration's own rule, not a main-key-only check")
        guard let hintCase = builder.range(of: "case .translateHint(let title):"),
              let nextCase = builder.range(of: "case .", range: hintCase.upperBound..<builder.endIndex)
        else {
            Issue.record("translateHint case not found in builder")
            return
        }
        #expect(builder[hintCase.upperBound..<nextCase.lowerBound].contains("menu.addItem(disabled(title))"),
                "the translate hint must render as a disabled informational line")
    }

    /// The header's RENDERED order, which the model cannot pin: the two persistent
    /// rows — the fn-conflict notice and the update line — are appended from the
    /// arms of two different cases, so they hold their slot even while hidden and
    /// the model's item order alone decides nothing about where they land. Order
    /// pinned here: status line, then the fn-conflict notice (status arm), then the
    /// translate hint with the update row directly after it (hint arm), so the two
    /// key hints stay adjacent and the update line never splits them.
    /// Stated sensitivity: move `makeUpdateItem()` back into the status arm (which
    /// puts it between the two key hints), or append it before the hint's own
    /// `menu.addItem` → the in-order `#expect` reddens.
    @Test
    func menuBuilderKeepsTheHeaderRowOrder() throws {
        let builder = try Self.strippedCode("Sources/slovo/DictationMenuBuilder.swift")
        guard let statusCase = builder.range(of: "case .status(let title):"),
              let nextCase = builder.range(of: "case .", range: statusCase.upperBound..<builder.endIndex)
        else {
            Issue.record("status case not found in builder")
            return
        }
        let statusBody = String(builder[statusCase.upperBound..<nextCase.lowerBound])
        #expect(Self.containsInOrder(["menu.addItem(entry)", "makeFnConflictItem()"], in: statusBody),
                "the header must render as the status line, then the fn-conflict row")
        #expect(!statusBody.contains("makeUpdateItem()"),
                "the update row must not render inside the status arm: that puts it between the two key hints")

        guard let hintCase = builder.range(of: "case .translateHint(let title):"),
              let afterHint = builder.range(of: "case .", range: hintCase.upperBound..<builder.endIndex)
        else {
            Issue.record("translateHint case not found in builder")
            return
        }
        let hintBody = String(builder[hintCase.upperBound..<afterHint.lowerBound])
        #expect(Self.containsInOrder(["menu.addItem(disabled(title))", "makeUpdateItem()"], in: hintBody),
                "the update row must render directly after the translate hint")
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

    /// The menu's add-key affordance must actually OPEN THE KEY WINDOW and route its
    /// Save through the app's key-save funnel — pinning the selector name alone is not
    /// enough: a no-op body, or one that opened Settings, or one whose onSave bypassed
    /// the funnel, would still satisfy a name-only guard yet defeat the affordance.
    /// Scope to the method body and assert it constructs and shows OpenRouterKeyWindow
    /// with onSave wired to saveOpenRouterKey.
    /// Stated sensitivity: empty the body (a no-op), open Settings instead, or route
    /// onSave anywhere but `saveOpenRouterKey` (bypassing the funnel) → RED.
    @Test
    func addKeySelectorOpensTheKeyWindowThroughTheFunnel() throws {
        let delegate = try Self.strippedCode("Sources/slovo/AppDelegate.swift")
        guard let head = delegate.range(of: "func showAddOpenRouterKeyWindow"),
              let nextFunc = delegate.range(of: "func ", range: head.upperBound..<delegate.endIndex)
        else {
            Issue.record("showAddOpenRouterKeyWindow not found")
            return
        }
        let body = delegate[head.upperBound..<nextFunc.lowerBound]
        #expect(body.contains("OpenRouterKeyWindow(onSave:"),
                "the add-key affordance must build the dedicated key window")
        #expect(body.contains("saveOpenRouterKey"),
                "the window's Save must route through the existing key-save funnel, not a new path")
        #expect(body.contains("openRouterKeyWindow?.show()"),
                "the add-key affordance must actually show the window")
    }

    /// The key window rebuilds a fresh view on every show (no stale key lingering in
    /// the field on reopen) and its secure field grabs first responder on join, via
    /// the codebase's proven NSView route (SwiftUI @FocusState-on-appear is unreliable
    /// in a hosted window). Stated sensitivity: reuse the stale view (drop the
    /// contentViewController reassignment), or remove the first-responder override /
    /// assignment / call → the corresponding expectation goes RED.
    @Test
    func keyWindowRebuildsViewAndFocusesTheKeyField() throws {
        let source = try Self.strippedCode("Sources/slovo/Settings/OpenRouterKeyWindow.swift")
        #expect(source.contains("windowController.window?.contentViewController = NSHostingController(rootView: view)"))
        #expect(source.contains("NSSecureTextField"))
        #expect(source.contains("override func viewDidMoveToWindow()"))
        #expect(source.contains("window.initialFirstResponder = self"))
        #expect(source.contains("window.makeFirstResponder(self)"))
    }

    /// The key window's Save routes the trimmed key through `onSave` (wired to the
    /// save funnel by the presenter) and closes; Cancel closes WITHOUT saving; an
    /// empty key cannot be saved; Esc cancels; the app activates before showing (the
    /// `.accessory` quirk). Stated sensitivity: wire Cancel to save, drop the
    /// empty-key guard, drop the Esc shortcut, or drop the activate → RED.
    @Test
    func keyWindowSaveThroughOnSaveAndCancelDoesNotSave() throws {
        let source = try Self.strippedCode("Sources/slovo/Settings/OpenRouterKeyWindow.swift")
        #expect(source.contains(#"Button("Save", action: save)"#))
        #expect(source.contains("onSave(trimmedKey)"))
        #expect(source.contains(#"Button("Cancel", action: onCancel)"#))
        #expect(source.contains(".disabled(trimmedKey.isEmpty)"))
        #expect(source.contains(".keyboardShortcut(.cancelAction)"))
        #expect(source.contains("NSApp.activate(ignoringOtherApps: true)"))
        #expect(source.contains("self?.close()"))
    }

    /// Saving must CLOSE the window itself — otherwise a window still holding the
    /// entered secret lingers and a second save is possible. Scope to the onSave
    /// closure body: a file-wide `close()` check is satisfied by onCancel's close
    /// alone, so removing close from onSave would survive it.
    /// Stated sensitivity: drop `self?.close()` from the onSave closure (leaving
    /// onCancel's) → RED; onCancel's close alone must not satisfy this.
    @Test
    func keyWindowClosesItselfOnSave() throws {
        let source = try Self.strippedCode("Sources/slovo/Settings/OpenRouterKeyWindow.swift")
        guard let onSaveStart = source.range(of: "onSave: {"),
              let closeBrace = source.range(of: "}", range: onSaveStart.upperBound..<source.endIndex)
        else {
            Issue.record("onSave closure not found")
            return
        }
        let onSaveClosure = source[onSaveStart.upperBound..<closeBrace.lowerBound]
        #expect(onSaveClosure.contains("close()"),
                "saving must close the window itself — a window holding the secret must not linger, and a second save must be impossible")
    }

    /// The key window is lazily built ONCE and reused (the VocabularyQuickAdd
    /// single-window discipline): the presenter guards on `openRouterKeyWindow == nil`
    /// before constructing. Dropping the guard spawns a fresh window + controller on
    /// every open, leaking controllers and stacking duplicate windows.
    /// Stated sensitivity: drop the `openRouterKeyWindow == nil` guard (construct
    /// unconditionally per open) → RED.
    @Test
    func keyWindowIsASingleReusedInstance() throws {
        let delegate = try Self.strippedCode("Sources/slovo/AppDelegate.swift")
        guard let head = delegate.range(of: "func showAddOpenRouterKeyWindow"),
              let nextFunc = delegate.range(of: "func ", range: head.upperBound..<delegate.endIndex)
        else {
            Issue.record("showAddOpenRouterKeyWindow not found")
            return
        }
        let body = delegate[head.upperBound..<nextFunc.lowerBound]
        #expect(body.contains("openRouterKeyWindow == nil"),
                "the window must be built once and reused, not respawned per open (which leaks controllers and stacks windows)")
    }

    /// `makeMenu` hands the builder its input whole and the live rows, and the
    /// builder reads every configuration value from that input; the model submenu
    /// reads its parameters. With these signatures, a menu read of a value outside
    /// the arguments fails. The scan has a limit: a helper that reads the store
    /// under another name passes it.
    /// Stated sensitivity: hand `make` anything but `input`, or hardcode
    /// `HotkeyConfiguration(main: .fn, …)` or `selectedModelId: ""` in the builder →
    /// RED; read `store.` in `makeMenu`, `modelMenu` or the builder → RED.
    /// Stated sensitivity: read the live fn reader or the updater coordinator
    /// inside makeMenu → RED. The build function reads its arguments only, so a
    /// rebuild draws the state the build subscriber read.
    @Test
    func makeMenuFeedsBuilderTheRealConfig() throws {
        let delegate = try Self.strippedCode("Sources/slovo/AppDelegate.swift")
        let makeMenu = try Self.blockBody(after: "func makeMenu", in: delegate)
        #expect(makeMenu.contains(".make(input, rows: rows)"))
        let builder = try Self.strippedCode("Sources/slovo/DictationMenuBuilder.swift")
        #expect(builder.contains("let hotkeys = input.hotkeyConfiguration"))
        #expect(builder.contains("selectedModelId: input.cleanupModelSelection.effective"))
        let cleanupMenu = try Self.strippedCode("Sources/slovo/AppDelegate+CleanupMenu.swift")
        let modelMenu = try Self.blockBody(after: "func modelMenu", in: cleanupMenu)
        for (name, body) in [("makeMenu", makeMenu), ("modelMenu", modelMenu), ("DictationMenuBuilder.swift", builder)] {
            #expect(!body.contains("store."), "\(name) must read only its input, never the store")
        }
        // The build function reads its arguments only: the fn verdict and the update
        // indication arrive as arguments, read from state by the build subscriber.
        #expect(!makeMenu.contains("fnKeyAssignmentReader"),
                "makeMenu must take the fn verdict as its argument, not from the live reader")
        #expect(!makeMenu.contains("updaterCoordinator"),
                "makeMenu must take the update indication as its argument, not from the coordinator")
    }

    private static func containsInOrder(_ needles: [String], in source: String) -> Bool {
        var searchStart = source.startIndex
        for needle in needles {
            guard let range = source.range(of: needle, range: searchStart..<source.endIndex) else { return false }
            searchStart = range.upperBound
        }
        return true
    }

    /// The brace-balanced block that opens right after `anchor` — a function body or
    /// a trailing closure. Scoping an assertion to it keeps a token found elsewhere in
    /// the file from satisfying a check about this one block.
    private static func blockBody(after anchor: String, in source: String) throws -> String {
        guard let anchorRange = source.range(of: anchor),
              let openBrace = source[anchorRange.upperBound...].firstIndex(of: "{")
        else {
            throw NSError(domain: "SettingsSurfaceSourceGuard", code: 1)
        }
        var depth = 0
        var index = openBrace
        while index < source.endIndex {
            if source[index] == "{" {
                depth += 1
            } else if source[index] == "}" {
                depth -= 1
                if depth == 0 { return String(source[openBrace...index]) }
            }
            index = source.index(after: index)
        }
        throw NSError(domain: "SettingsSurfaceSourceGuard", code: 2)
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
