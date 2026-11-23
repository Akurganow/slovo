import AppKit
import SlovoTestSupport
import Testing
@testable import slovo
@testable import SlovoCore

/// The dictation dropdown's key-dependent rows and header order, built by
/// `DictationMenuBuilder` over an `AppDelegate` from `TestAppDelegate`.
@MainActor
@Suite("Dictation menu header and cleanup rows")
struct DictationMenuHeaderRowTests {
    /// With no key stored, the cleanup block is the single Add OpenRouter Key row,
    /// which opens the key window, and none of the cleanup rows appear.
    /// Stated sensitivity: the row's title changes, it calls another action or loses
    /// its target, or the cleanup rows show without a key → RED. The action is not
    /// called: it opens a window.
    @Test
    func menuWithoutAKeyOffersAddKeyAndNoCleanupRows() throws {
        let shell = TestAppDelegate(isKeyStored: false)

        let menu = shell.buildMenu().menu

        let row = try #require(menu.item(exactly: "Add OpenRouter Key…"))
        #expect(row.action == #selector(AppDelegate.showAddOpenRouterKeyWindow))
        #expect(row.target === shell.appUnderTest)
        #expect(menu.item(exactly: "Clean Up Dictation") == nil)
        #expect(menu.item(startingWith: "Cleanup Model:") == nil)
        #expect(menu.item(startingWith: "Translate to:") == nil)
    }

    /// With a key stored, the model and translate rows are enabled while cleanup is on
    /// and disabled while it is off; the Clean Up row stays in both states.
    /// Stated sensitivity: the model row's enabled flag is fixed, or the translate
    /// row's enabled flag is fixed or dropped → RED.
    @Test
    func modelAndTranslateRowsFollowTheCleanupToggle() throws {
        let shell = TestAppDelegate()
        for isOn in [true, false] {
            shell.store.update { $0.config.cleanupEnabled = isOn }
            let menu = shell.buildMenu().menu

            #expect(try #require(menu.item(startingWith: "Cleanup Model:")).isEnabled == isOn)
            #expect(try #require(menu.item(startingWith: "Translate to:")).isEnabled == isOn)
            #expect(menu.item(exactly: "Clean Up Dictation") != nil)
        }
    }

    /// The fn-conflict row exists whenever fn holds either key role and not otherwise,
    /// is hidden until macOS claims fn, and is the delegate's persistent row.
    /// Stated sensitivity: the row is created only when fn is the main key, or for
    /// every key → RED; the build-time verdict no longer reveals the row → RED.
    @Test
    func fnConflictRowExistsWhenFnHoldsEitherRole() {
        let cases: [(main: HotkeyTrigger, translate: HotkeyTrigger, hasRow: Bool)] = [
            (.fn, .control, true),
            (.leftCommand, .fn, true),
            (.leftCommand, .control, false),
        ]
        for keys in cases {
            let shell = TestAppDelegate()
            shell.store.update {
                $0.config.trigger = keys.main
                $0.config.translateTrigger = keys.translate
            }

            let hidden = shell.buildMenu(isFnKeySystemAssigned: false).menu
            let row = hidden.item(exactly: DictationMenu.fnConflictRemedy)
            #expect((row != nil) == keys.hasRow)
            #expect((shell.appUnderTest.fnConflictMenuItem != nil) == keys.hasRow)
            #expect(row?.isHidden != false)

            let revealed = shell.buildMenu(isFnKeySystemAssigned: true).menu
            #expect((revealed.item(exactly: DictationMenu.fnConflictRemedy)?.isHidden == false) == keys.hasRow)
        }
    }

    /// The translate hint is a disabled row with no action.
    /// Stated sensitivity: the hint arm is emptied so no hint row exists, or the hint
    /// becomes clickable (enabled or given an action) → RED.
    @Test
    func translateHintIsADisabledRow() throws {
        let shell = TestAppDelegate()

        let hint = try #require(shell.buildMenu().menu.item(exactly: "Add ⌃ to translate"))

        #expect(!hint.isEnabled)
        #expect(hint.action == nil)
    }

    /// The header rows keep their order, checked by item identity: the fn-conflict row
    /// follows the status line, the translate hint follows the fn row, and the update
    /// row follows the hint.
    /// Stated sensitivity: the fn row moves away from the status line, the update row
    /// moves into the status arm, or the update row is added before the hint → RED.
    @Test
    func headerRowsKeepTheirOrder() throws {
        let shell = TestAppDelegate()
        let built = shell.buildMenu()
        let items = built.menu.items

        let statusIndex = try #require(items.firstIndex { $0 === built.statusItem })
        let fnRow = try #require(shell.appUnderTest.fnConflictMenuItem)
        let updateRow = try #require(shell.appUnderTest.updateMenuItem)
        #expect(items[statusIndex + 1] === fnRow)
        #expect(items[statusIndex + 2].title == "Add ⌃ to translate")
        #expect(items[statusIndex + 3] === updateRow)
    }

    /// The Clean Up Dictation row shows the preference as its checkmark and is
    /// actionable in both states: it is the way back on from off.
    /// Stated sensitivity: the checkmark is dropped, inverted or fixed, or the row is
    /// rendered disabled, directly or through the `disabled` helper → RED.
    @Test
    func cleanupToggleIsAlwaysActionableAndShowsThePreference() throws {
        let shell = TestAppDelegate()
        for isOn in [true, false] {
            shell.store.update { $0.config.cleanupEnabled = isOn }
            let menu = shell.buildMenu().menu

            let row = try #require(menu.item(exactly: "Clean Up Dictation"))
            #expect(row.state == (isOn ? .on : .off))
            #expect(row.isEnabled)
            #expect(row.action == #selector(AppDelegate.toggleCleanupDictation(_:)))
            #expect(row.target === shell.appUnderTest)
        }
    }
}
