import AppKit
import Testing
@testable import slovo
@testable import SlovoCore

/// The dictation dropdown's overall shape and its Mute row: the rows in order with
/// their keys and icon, built by `DictationMenuBuilder` over an `AppDelegate` from
/// `AppShellFixture`. Rows are read by title, state, enabled flag, action, target,
/// key equivalent and order, never by image.
@MainActor
@Suite("Dictation menu rows")
struct DictationMenuRowTests {
    /// The Mute row is a checkmark toggle: the builder stores it for the availability
    /// renderer, it follows the preference, and its click flips the preference.
    /// Stated sensitivity: the builder stops storing the item, the title changes, the
    /// checkmark is dropped, inverted or fixed, or the row calls another action → RED.
    @Test
    func muteRowIsACheckmarkToggleTheRendererCanReach() throws {
        let shell = AppShellFixture()
        for isOn in [true, false] {
            shell.store.update { $0.config.mutesSystemAudioWhileDictating = isOn }
            let menu = shell.buildMenu().menu

            let row = try #require(menu.item(exactly: "Mute Audio While Dictating"))
            #expect(shell.app.muteMenuItem === row)
            #expect(row.state == (isOn ? .on : .off))
            #expect(row.action == #selector(AppDelegate.toggleMuteWhileDictating(_:)))
            #expect(row.target === shell.app)
            row.click()
            #expect(shell.store.state.config.mutesSystemAudioWhileDictating == !isOn)
        }
    }

    /// The menu has its rows in order with their keys: Settings with "," and an icon,
    /// About, Quit with "q", and the status row carrying the bare status text. The
    /// cleanup model and the translate target are set first, so the titles do not
    /// depend on the defaults.
    /// Stated sensitivity: the menu is built from another list, the status line gets a
    /// prefix, Settings or About call another action or lose their target, the "," or
    /// "q" key changes, the Settings icon is removed, or the ellipsis leaves
    /// "Add Vocabulary…" or "Settings…" → RED. Swapping the icon for another symbol
    /// is not caught: telling two symbols apart needs a pixel comparison.
    @Test
    func menuShowsItsRowsKeysAndSettingsIcon() throws {
        let shell = AppShellFixture()
        shell.store.update {
            $0.config.openRouterModel = "anthropic/claude-haiku-5.5"
            $0.config.translationTargetLanguage = Language(rawValue: "ru")
        }
        let built = shell.buildMenu(statusLine: "Hold fn to talk")
        let menu = built.menu

        // Separators have no title. The update row is told apart by identity.
        let titles = menu.items.map { $0 === shell.app.updateMenuItem ? "<update row>" : $0.title }
        #expect(titles == [
            "Hold fn to talk", DictationMenu.fnConflictRemedy, "Add ⌃ to translate", "<update row>",
            "",
            "Clean Up Dictation", "Cleanup Model: Claude Haiku 5.5", "Translate to: Russian",
            "",
            "Add Vocabulary…", "Microphone", "Mute Audio While Dictating", "Sound Cues",
            "",
            "Settings…", "About Slovo", "Quit Slovo",
        ])
        #expect(built.statusItem.title == "Hold fn to talk")

        let settings = try #require(menu.item(exactly: "Settings…"))
        #expect(settings.action == #selector(AppDelegate.showSettingsWindow))
        #expect(settings.target === shell.app)
        #expect(settings.keyEquivalent == ",")
        #expect(settings.image != nil)

        let about = try #require(menu.item(exactly: "About Slovo"))
        #expect(about.action == #selector(AppDelegate.showAboutPane))
        #expect(about.target === shell.app)

        let quit = try #require(menu.item(exactly: "Quit Slovo"))
        #expect(quit.action == #selector(NSApplication.terminate(_:)))
        #expect(quit.keyEquivalent == "q")
    }
}
