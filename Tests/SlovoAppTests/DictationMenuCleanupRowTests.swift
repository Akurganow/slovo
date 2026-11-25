import AppKit
import Testing
@testable import slovo
@testable import SlovoCore

/// The dictation dropdown's cleanup block: the Clean Up Dictation toggle, the Cleanup
/// Model and Translate submenus, and the Add OpenRouter Key row that replaces them
/// while no key is stored. Built by `DictationMenuBuilder` over an `AppDelegate` from
/// `AppShellFixture`.
@MainActor
@Suite("Dictation menu cleanup rows")
struct DictationMenuCleanupRowTests {
    private let haiku = "anthropic/claude-haiku-5.5"
    private let qwen = "qwen/qwen3.8-flash"

    /// The Cleanup Model row names the selected model's display name, checks exactly
    /// that model in its submenu, and a click on another row writes that row's id.
    /// Stated sensitivity: the row title loses "Cleanup Model: " or shows the raw id,
    /// a wrong selected model is passed, the rows lose their `representedObject`,
    /// the click's cast targets the wrong type, or the click writes another field or
    /// a fixed value → RED. The start model (Haiku) and the clicked model (Qwen)
    /// both differ from the default, so a write of the default is no equal update.
    @Test
    func cleanupModelRowShowsTheSelectedModelAndWritesTheChosenId() throws {
        let shell = AppShellFixture()
        shell.store.update { $0.config.openRouterModel = haiku }
        let menu = shell.buildMenu().menu

        let row = try #require(menu.item(exactly: "Cleanup Model: Claude Haiku 5.5"))
        let submenu = try #require(row.submenu)
        #expect(submenu.items.map(\.title) == CleanupModelCatalog.options.map(\.displayName))
        #expect(submenu.items.filter { $0.state == .on }.map(\.title) == ["Claude Haiku 5.5"])
        for item in submenu.items {
            #expect(item.action == #selector(AppDelegate.selectCleanupModel(_:)))
            #expect(item.target === shell.app)
        }

        let chosen = try #require(submenu.item(exactly: "Qwen3.8 Flash"))
        chosen.click()
        #expect(shell.store.state.config.openRouterModel == qwen)
    }

    /// The model submenu lists exactly the options it is given, checking the selected
    /// one. A call through the menu cannot see this: its default options are the
    /// whole catalog.
    /// Stated sensitivity: the submenu lists the whole catalog instead of its options,
    /// or the checkmark is inverted, dropped or fixed → RED.
    @Test
    func cleanupModelSubmenuListsOnlyTheGivenOptions() throws {
        let shell = AppShellFixture()
        let options = [
            CleanupModelOption(id: "test/one", displayName: "One"),
            CleanupModelOption(id: "test/two", displayName: "Two"),
        ]

        let parent = shell.app.modelMenu(title: "Pick", options: options, selectedModel: "test/two")

        #expect(parent.title == "Pick")
        let rows = try #require(parent.submenu).items
        #expect(rows.map(\.title) == ["One", "Two"])
        #expect(rows.map(\.state) == [.off, .on])
    }

    /// The Translate submenu lists the recognition-language catalog with no Auto row,
    /// checks only the stored target, and a click writes that row's language.
    /// Stated sensitivity: the rows come from another list, a row's action is dropped
    /// or changed, the click writes another field or a fixed language, the checkmark
    /// is dropped or its condition negated, or an Auto row is added under any
    /// spelling → RED.
    @Test
    func translateSubmenuListsTheCatalogWithoutAutoAndWritesTheTarget() throws {
        let shell = AppShellFixture()
        let menu = shell.buildMenu().menu

        let row = try #require(menu.item(exactly: "Translate to: English"))
        let submenu = try #require(row.submenu)
        let catalog = RecognitionLanguageCatalog.options
        #expect(submenu.items.map(\.title) == catalog.map(\.displayName))
        #expect(!submenu.items.contains { $0.title.lowercased() == "auto" })
        #expect(submenu.items.filter { $0.state == .on }.map(\.title) == ["English"])
        for item in submenu.items {
            #expect(item.action == #selector(AppDelegate.selectTranslationLanguage(_:)))
            #expect(item.target === shell.app)
        }

        try #require(submenu.item(exactly: "Russian")).click()
        #expect(shell.store.state.config.translationTargetLanguage == Language(rawValue: "ru"))
    }

    /// With no key stored, the cleanup block is the single Add OpenRouter Key row,
    /// which opens the key window, and none of the cleanup rows appear.
    /// Stated sensitivity: the row's title changes, it calls another action or loses
    /// its target, or the cleanup rows show without a key → RED. The action is not
    /// called: it opens a window.
    @Test
    func menuWithoutAKeyOffersAddKeyAndNoCleanupRows() throws {
        let shell = AppShellFixture(isKeyStored: false)

        let menu = shell.buildMenu().menu

        let row = try #require(menu.item(exactly: "Add OpenRouter Key…"))
        #expect(row.action == #selector(AppDelegate.showAddOpenRouterKeyWindow))
        #expect(row.target === shell.app)
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
        let shell = AppShellFixture()
        for isOn in [true, false] {
            shell.store.update { $0.config.cleanupEnabled = isOn }
            let menu = shell.buildMenu().menu

            #expect(try #require(menu.item(startingWith: "Cleanup Model:")).isEnabled == isOn)
            #expect(try #require(menu.item(startingWith: "Translate to:")).isEnabled == isOn)
            #expect(menu.item(exactly: "Clean Up Dictation") != nil)
        }
    }

    /// The Clean Up Dictation row shows the preference as its checkmark and is
    /// actionable in both states: it is the way back on from off.
    /// Stated sensitivity: the checkmark is dropped, inverted or fixed, or the row is
    /// rendered disabled, directly or through the `disabled` helper → RED.
    @Test
    func cleanupToggleIsAlwaysActionableAndShowsThePreference() throws {
        let shell = AppShellFixture()
        for isOn in [true, false] {
            shell.store.update { $0.config.cleanupEnabled = isOn }
            let menu = shell.buildMenu().menu

            let row = try #require(menu.item(exactly: "Clean Up Dictation"))
            #expect(row.state == (isOn ? .on : .off))
            #expect(row.isEnabled)
            #expect(row.action == #selector(AppDelegate.toggleCleanupDictation(_:)))
            #expect(row.target === shell.app)
        }
    }
}
