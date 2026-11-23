import AppKit
import Testing
@testable import slovo
@testable import SlovoCore

/// The dictation dropdown's header rows above the cleanup block: the fn-conflict
/// row, the translate hint and the update row, built by `DictationMenuBuilder` over
/// an `AppDelegate` from `AppShellFixture`.
@MainActor
@Suite("Dictation menu header rows")
struct DictationMenuHeaderRowTests {
    /// A standalone translate key reads "Hold <key> to translate", where an additional
    /// one reads "Add <key> to translate": the hint follows the stored key pair.
    /// Stated sensitivity: the builder is handed a fixed key configuration instead of
    /// the stored one → RED, since the hint then names ⌃ and "Add".
    @Test
    func translateHintNamesAStandaloneTranslateKey() {
        let shell = AppShellFixture()
        shell.store.update {
            $0.config.trigger = .fn
            $0.config.translateTrigger = .leftShift
            $0.config.translateKeyIsAdditional = false
        }

        let menu = shell.buildMenu().menu

        #expect(menu.items.map(\.title).filter { $0.hasSuffix(" to translate") } == ["Hold Left ⇧ to translate"])
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
            let shell = AppShellFixture()
            shell.store.update {
                $0.config.trigger = keys.main
                $0.config.translateTrigger = keys.translate
            }

            let hidden = shell.buildMenu(isFnKeySystemAssigned: false).menu
            let row = hidden.item(exactly: DictationMenu.fnConflictRemedy)
            #expect((row != nil) == keys.hasRow)
            #expect((shell.app.fnConflictMenuItem != nil) == keys.hasRow)
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
        let shell = AppShellFixture()

        let hint = try #require(shell.buildMenu().menu.item(exactly: "Add ⌃ to translate"))

        #expect(!hint.isEnabled)
        #expect(hint.action == nil)
    }

    /// The header rows keep their order, checked by item identity: the fn-conflict row
    /// follows the status line, the translate hint follows the fn row, and the update
    /// row follows the hint.
    /// Stated sensitivity: the fn row moves away from the status line, the update row
    /// moves into the status arm, the update row is added before the hint, or the
    /// delegate's stored fn-conflict or update row is not the item placed in the
    /// menu → RED.
    @Test
    func headerRowsKeepTheirOrder() throws {
        let shell = AppShellFixture()
        let built = shell.buildMenu()
        let items = built.menu.items

        let statusIndex = try #require(items.firstIndex { $0 === built.statusItem })
        let fnRow = try #require(shell.app.fnConflictMenuItem)
        let updateRow = try #require(shell.app.updateMenuItem)
        #expect(items[statusIndex + 1] === fnRow)
        #expect(items[statusIndex + 2].title == "Add ⌃ to translate")
        #expect(items[statusIndex + 3] === updateRow)
    }
}
