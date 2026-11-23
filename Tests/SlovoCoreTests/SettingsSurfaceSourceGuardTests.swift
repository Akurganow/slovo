import Foundation
import Testing

// No test target depends on the `slovo` executable, so the menu renderer cannot be
// exercised; these guards read its comment-stripped source. What SlovoCore decides
// (the item list, the enabled flags) is tested in DictationMenuTests and AppStateTests,
// not here.
@Suite("Settings surface source guards")
struct SettingsSurfaceSourceGuardTests {
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
        let builder = try SourceText.code("Sources/slovo/DictationMenuBuilder.swift")
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
        let builder = try SourceText.code("Sources/slovo/DictationMenuBuilder.swift")
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
        let builder = try SourceText.code("Sources/slovo/DictationMenuBuilder.swift")
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
        let builder = try SourceText.code("Sources/slovo/DictationMenuBuilder.swift")
        guard let statusCase = builder.range(of: "case .status(let title):"),
              let nextCase = builder.range(of: "case .", range: statusCase.upperBound..<builder.endIndex)
        else {
            Issue.record("status case not found in builder")
            return
        }
        let statusBody = String(builder[statusCase.upperBound..<nextCase.lowerBound])
        #expect(SourceText.containsInOrder(["menu.addItem(entry)", "makeFnConflictItem()"], in: statusBody),
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
        #expect(SourceText.containsInOrder(["menu.addItem(disabled(title))", "makeUpdateItem()"], in: hintBody),
                "the update row must render directly after the translate hint")
    }

    /// The cleanup toggle renders as an always-actionable item — the type narrowing to
    /// `isOn` removed the off-and-disabled path — with its checkmark driven by `isOn`.
    /// Stated sensitivity: render the toggle disabled (`isEnabled = false` or the
    /// `disabled(_:)` helper), or stop driving the state from `isOn` → RED.
    @Test
    func menuBuilderRendersCleanupToggleAsActionable() throws {
        let builder = try SourceText.code("Sources/slovo/DictationMenuBuilder.swift")
        guard let toggleCase = builder.range(of: "case .cleanupToggle(let isOn):"),
              let nextCase = builder.range(of: "case .", range: toggleCase.upperBound..<builder.endIndex)
        else {
            Issue.record("cleanupToggle case not found in builder")
            return
        }
        let toggleCaseBody = builder[toggleCase.upperBound..<nextCase.lowerBound]
        #expect(toggleCaseBody.contains("entry.state = isOn ? .on : .off"),
                "the toggle's checkmark must track isOn")
        #expect(!toggleCaseBody.contains("isEnabled") && !toggleCaseBody.contains("disabled("),
                "the toggle must be actionable — the arm renders no disabled item")
    }
}
