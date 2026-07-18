import Testing

import SlovoCore

// The dropdown's ordered top-level items and its dynamic "Hold <key> to talk"
// hint, verified without a running status bar.
@Suite("Dictation menu model")
struct DictationMenuTests {
    /// The items appear in the fixed spec order, grouped by role: header (title,
    /// status, hotkey hint), separator, live switches (cleanup-model,
    /// translation-language, mute-while-dictating), separator, window openers
    /// (add-vocabulary, about, settings), separator, quit. The mute switch closes
    /// the live-switch group; Add Vocabulary opens the window-opener group; About
    /// sits between Add Vocabulary and Settings; Quit is isolated after its own
    /// separator.
    /// Stated sensitivity: reorder, drop, or misposition any item — or ignore the
    /// `mutesSystemAudioWhileDictating` arg — → the exact sequence mismatches → RED.
    @Test
    func itemsAppearInSpecOrder() {
        let items = DictationMenu.items(
            trigger: .fn,
            selectedModelId: "openai/gpt-5.6-luna",
            mutesSystemAudioWhileDictating: true,
            translationLanguage: "en"
        )
        #expect(items == [
            .title("Slovo"),
            .status("Idle"),
            .hotkeyHint("Hold fn to talk"),
            .separator,
            .cleanupModel(selectedModelId: "openai/gpt-5.6-luna"),
            .translationLanguage(selected: "en"),
            .muteWhileDictating(isOn: true),
            .separator,
            .addVocabulary,
            .about,
            .settings,
            .separator,
            .quit,
        ])
    }

    /// The About entry lives in the window-opener group: it directly follows Add
    /// Vocabulary and sits directly before Settings (About convention keeps it just
    /// above Settings). Quit is isolated after its own trailing separator.
    /// Stated sensitivity: drop `.about` → it is absent → RED; move it out of the
    /// after-add-vocabulary / before-settings slot → the ordered-neighbour asserts
    /// redden.
    @Test
    func aboutItemSitsBetweenAddVocabularyAndSettings() {
        let items = DictationMenu.items(
            trigger: .fn,
            selectedModelId: "m",
            mutesSystemAudioWhileDictating: true,
            translationLanguage: "en"
        )
        #expect(items.contains(.about))

        guard let addVocabularyIndex = items.firstIndex(of: .addVocabulary),
              let aboutIndex = items.firstIndex(of: .about),
              let settingsIndex = items.firstIndex(of: .settings)
        else {
            Issue.record("add-vocabulary, about, and settings items must all be present: \(items)")
            return
        }
        #expect(aboutIndex == addVocabularyIndex + 1, "about must sit right after Add Vocabulary")
        #expect(settingsIndex == aboutIndex + 1, "settings must directly follow about")
    }

    /// AC9: passing the flag as `false` yields `.muteWhileDictating(isOn: false)` in
    /// the same pinned position — proving the item reflects the argument, not a
    /// hard-coded on/off.
    /// Stated sensitivity: hard-code the item's `isOn`, drop the item, or move it out
    /// of the after-translation-language / before-separator slot → the exact
    /// sequence mismatches → RED.
    @Test
    func muteWhileDictatingItemReflectsDisabledFlagAndPosition() {
        let items = DictationMenu.items(
            trigger: .fn,
            selectedModelId: "x",
            mutesSystemAudioWhileDictating: false,
            translationLanguage: "en"
        )
        #expect(items == [
            .title("Slovo"),
            .status("Idle"),
            .hotkeyHint("Hold fn to talk"),
            .separator,
            .cleanupModel(selectedModelId: "x"),
            .translationLanguage(selected: "en"),
            .muteWhileDictating(isOn: false),
            .separator,
            .addVocabulary,
            .about,
            .settings,
            .separator,
            .quit,
        ])
    }

    /// U1 — the translation-language item carries the selected target code and sits
    /// directly between cleanup-model and mute-while-dictating (mirroring
    /// cleanup-model's selected-id contract), inside the live-switch group.
    /// Stated sensitivity: drop the item → it is absent → RED; misorder it (not right
    /// after cleanup-model) → the ordered-neighbour assert reddens; hardcode/drop the
    /// selected code → `.translationLanguage(selected: "ru")` mismatches → RED.
    @Test
    func translationLanguageItemFollowsCleanupModel() {
        let items = DictationMenu.items(trigger: .fn, selectedModelId: "m", mutesSystemAudioWhileDictating: true, translationLanguage: "ru")
        #expect(items.contains(.translationLanguage(selected: "ru")))

        guard let cleanupIndex = items.firstIndex(of: .cleanupModel(selectedModelId: "m")),
              let translationIndex = items.firstIndex(of: .translationLanguage(selected: "ru")),
              let muteIndex = items.firstIndex(of: .muteWhileDictating(isOn: true))
        else {
            Issue.record("cleanup-model, translation-language, and mute-while-dictating items must all be present: \(items)")
            return
        }
        #expect(translationIndex == cleanupIndex + 1, "translation-language must sit right after cleanup-model")
        #expect(muteIndex == translationIndex + 1, "mute-while-dictating must directly follow translation-language")
    }

    /// The hint uses the trigger's display name, not its wire value.
    /// Stated sensitivity: build the hint from `trigger.rawValue` (or a fixed "fn")
    /// → "Hold right-command to talk" ≠ "Hold Right ⌘ to talk" → RED.
    @Test
    func hotkeyHintUsesTriggerDisplayName() {
        let items = DictationMenu.items(trigger: .rightCommand, selectedModelId: "x", mutesSystemAudioWhileDictating: true, translationLanguage: "en")
        #expect(items.contains(.hotkeyHint("Hold Right ⌘ to talk")))
    }

    /// The cleanup-model item carries the selected id so the builder can check the
    /// right catalog row.
    /// Stated sensitivity: hard-code or drop the id → the wrong row would be
    /// checked → RED.
    @Test
    func cleanupModelItemCarriesSelectedId() {
        let items = DictationMenu.items(
            trigger: .fn,
            selectedModelId: "anthropic/claude-haiku-4.5",
            mutesSystemAudioWhileDictating: true,
            translationLanguage: "en"
        )
        #expect(items.contains(.cleanupModel(selectedModelId: "anthropic/claude-haiku-4.5")))
    }
}
