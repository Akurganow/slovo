import AppKit
import SlovoTestSupport
import Testing
@testable import slovo
@testable import SlovoCore

/// The dictation dropdown's rows, built by `DictationMenuBuilder` over an
/// `AppDelegate` from `TestAppDelegate`. Rows are read by title, state, enabled
/// flag, action, target, key equivalent and order, never by image.
@MainActor
@Suite("Dictation menu rows")
struct DictationMenuRowTests {
    private let haiku = "anthropic/claude-haiku-5.5"
    private let gemini = "google/gemini-3.1-flash-lite"

    /// The Cleanup Model row names the selected model's display name, checks exactly
    /// that model in its submenu, and a click on another row writes that row's id.
    /// Stated sensitivity: the row title loses "Cleanup Model: " or shows the raw id,
    /// a wrong selected model is passed, the rows lose their `representedObject`,
    /// the click's cast targets the wrong type, or the click writes another field or
    /// a fixed value → RED. The start model (Haiku) and the clicked model (Gemini)
    /// both differ from the default, so a write of the default is no equal update.
    @Test
    func cleanupModelRowShowsTheSelectedModelAndWritesTheChosenId() throws {
        let shell = TestAppDelegate()
        shell.store.update { $0.config.openRouterModel = haiku }
        let menu = shell.buildMenu().menu

        let row = try #require(menu.item(exactly: "Cleanup Model: Claude Haiku 5.5"))
        let submenu = try #require(row.submenu)
        #expect(submenu.items.map(\.title) == CleanupModelCatalog.options.map(\.displayName))
        #expect(submenu.items.filter { $0.state == .on }.map(\.title) == ["Claude Haiku 5.5"])
        for item in submenu.items {
            #expect(item.action == #selector(AppDelegate.selectCleanupModel(_:)))
            #expect(item.target === shell.appUnderTest)
        }

        let chosen = try #require(submenu.item(exactly: "Gemini 3.1 Flash Lite"))
        chosen.click()
        #expect(shell.store.state.config.openRouterModel == gemini)
    }

    /// The model submenu lists exactly the options it is given, checking the selected
    /// one. A call through the menu cannot see this: its default options are the
    /// whole catalog.
    /// Stated sensitivity: the submenu lists the whole catalog instead of its options,
    /// or the checkmark is inverted, dropped or fixed → RED.
    @Test
    func cleanupModelSubmenuListsOnlyTheGivenOptions() throws {
        let shell = TestAppDelegate()
        let options = [
            CleanupModelOption(id: "test/one", displayName: "One"),
            CleanupModelOption(id: "test/two", displayName: "Two"),
        ]

        let parent = shell.appUnderTest.modelMenu(title: "Pick", options: options, selectedModel: "test/two")

        #expect(parent.title == "Pick")
        let rows = try #require(parent.submenu).items
        #expect(rows.map(\.title) == ["One", "Two"])
        #expect(rows.map(\.state) == [.off, .on])
    }

    /// The Mute row is a checkmark toggle: the builder stores it for the availability
    /// renderer, it follows the preference, and its click flips the preference.
    /// Stated sensitivity: the builder stops storing the item, the title changes, the
    /// checkmark is dropped, inverted or fixed, or the row calls another action → RED.
    @Test
    func muteRowIsACheckmarkToggleTheRendererCanReach() throws {
        let shell = TestAppDelegate()
        for isOn in [true, false] {
            shell.store.update { $0.config.mutesSystemAudioWhileDictating = isOn }
            let menu = shell.buildMenu().menu

            let row = try #require(menu.item(exactly: "Mute Audio While Dictating"))
            #expect(shell.appUnderTest.muteMenuItem === row)
            #expect(row.state == (isOn ? .on : .off))
            #expect(row.action == #selector(AppDelegate.toggleMuteWhileDictating(_:)))
            #expect(row.target === shell.appUnderTest)
            row.click()
            #expect(shell.store.state.config.mutesSystemAudioWhileDictating == !isOn)
        }
    }

    /// The Translate submenu lists the recognition-language catalog with no Auto row,
    /// checks only the stored target, and a click writes that row's language.
    /// Stated sensitivity: the rows come from another list, a row's action is dropped
    /// or changed, the click writes another field or a fixed language, the checkmark
    /// is dropped or its condition negated, or an Auto row is added under any
    /// spelling → RED.
    @Test
    func translateSubmenuListsTheCatalogWithoutAutoAndWritesTheTarget() throws {
        let shell = TestAppDelegate()
        let menu = shell.buildMenu().menu

        let row = try #require(menu.item(exactly: "Translate to: English"))
        let submenu = try #require(row.submenu)
        let catalog = RecognitionLanguageCatalog.options
        #expect(submenu.items.map(\.title) == catalog.map(\.displayName))
        #expect(!submenu.items.contains { $0.title.lowercased() == "auto" })
        #expect(submenu.items.filter { $0.state == .on }.map(\.title) == ["English"])
        for item in submenu.items {
            #expect(item.action == #selector(AppDelegate.selectTranslationLanguage(_:)))
            #expect(item.target === shell.appUnderTest)
        }

        try #require(submenu.item(exactly: "Russian")).click()
        #expect(shell.store.state.config.translationTargetLanguage == Language(rawValue: "ru"))
    }

    /// The menu has its rows in order with their keys: Settings with "," and an icon,
    /// About, Quit with "q", the model submenu wired to its action, and the status
    /// row carrying the bare status text.
    /// Stated sensitivity: the menu is built from another list, the status line gets a
    /// prefix, Settings or About call another action or lose their target, the "," or
    /// "q" key changes, the Settings icon is removed, the model submenu is dropped, or
    /// the ellipsis leaves "Add Vocabulary…" or "Settings…" → RED. Swapping the icon
    /// for another symbol is not caught: telling two symbols apart needs a pixel
    /// comparison.
    @Test
    func menuShowsItsRowsKeysAndSettingsIcon() throws {
        let shell = TestAppDelegate()
        let built = shell.buildMenu(statusLine: "Hold fn to talk")
        let menu = built.menu

        // Separators have no title. The update row is told apart by identity.
        let titles = menu.items.map { $0 === shell.appUnderTest.updateMenuItem ? "<update row>" : $0.title }
        #expect(titles == [
            "Hold fn to talk", DictationMenu.fnConflictRemedy, "Add ⌃ to translate", "<update row>",
            "",
            "Clean Up Dictation", "Cleanup Model: GPT-6 Luna", "Translate to: English",
            "",
            "Add Vocabulary…", "Microphone", "Mute Audio While Dictating", "Sound Cues",
            "",
            "Settings…", "About Slovo", "Quit Slovo",
        ])
        #expect(built.statusItem.title == "Hold fn to talk")

        let settings = try #require(menu.item(exactly: "Settings…"))
        #expect(settings.action == #selector(AppDelegate.showSettingsWindow))
        #expect(settings.target === shell.appUnderTest)
        #expect(settings.keyEquivalent == ",")
        #expect(settings.image != nil)

        let about = try #require(menu.item(exactly: "About Slovo"))
        #expect(about.action == #selector(AppDelegate.showAboutPane))
        #expect(about.target === shell.appUnderTest)

        let quit = try #require(menu.item(exactly: "Quit Slovo"))
        #expect(quit.action == #selector(NSApplication.terminate(_:)))
        #expect(quit.keyEquivalent == "q")

        let model = try #require(menu.item(startingWith: "Cleanup Model:"))
        let modelRows = try #require(model.submenu).items
        #expect(!modelRows.isEmpty)
        #expect(modelRows.allSatisfy { $0.action == #selector(AppDelegate.selectCleanupModel(_:)) })
    }

    /// A standalone translate key reads "Hold <key> to translate", where an additional
    /// one reads "Add <key> to translate": the hint follows the stored key pair.
    /// Stated sensitivity: the builder is handed a fixed key configuration instead of
    /// the stored one → RED, since the hint then names ⌃ and "Add".
    @Test
    func translateHintNamesAStandaloneTranslateKey() {
        let shell = TestAppDelegate()
        shell.store.update {
            $0.config.trigger = .fn
            $0.config.translateTrigger = .leftShift
            $0.config.translateKeyIsAdditional = false
        }

        let menu = shell.buildMenu().menu

        #expect(menu.items.map(\.title).filter { $0.hasSuffix(" to translate") } == ["Hold Left ⇧ to translate"])
    }
}
