import Testing

import SlovoCore

// The dropdown's ordered top-level items and its dynamic "Hold <key> to talk"
// hint, verified without a running status bar.
@Suite("Dictation menu model")
struct DictationMenuTests {
    /// The items appear in the fixed spec order: title, status, hotkey hint,
    /// separator, cleanup-model, translation-language, add-vocabulary,
    /// mute-while-dictating, separator, settings, quit. The translation-language
    /// item sits right after cleanup-model; the mute switch sits AFTER Add
    /// Vocabulary and BEFORE the trailing separator, carrying the live flag.
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
            .addVocabulary,
            .muteWhileDictating(isOn: true),
            .separator,
            .settings,
            .quit,
        ])
    }

    /// AC9: passing the flag as `false` yields `.muteWhileDictating(isOn: false)` in
    /// the same pinned position — proving the item reflects the argument, not a
    /// hard-coded on/off.
    /// Stated sensitivity: hard-code the item's `isOn`, drop the item, or move it out
    /// of the after-addVocabulary / before-trailing-separator slot → the exact
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
            .addVocabulary,
            .muteWhileDictating(isOn: false),
            .separator,
            .settings,
            .quit,
        ])
    }

    /// U1 — the translation-language item carries the selected target code and sits
    /// directly between cleanup-model and add-vocabulary (mirroring cleanup-model's
    /// selected-id contract). RED now: the model does not emit the item.
    /// Stated sensitivity: drop the item → it is absent → RED; misorder it (not right
    /// after cleanup-model) → the ordered-neighbour assert reddens; hardcode/drop the
    /// selected code → `.translationLanguage(selected: "ru")` mismatches → RED.
    @Test
    func translationLanguageItemFollowsCleanupModel() {
        let items = DictationMenu.items(trigger: .fn, selectedModelId: "m", mutesSystemAudioWhileDictating: true, translationLanguage: "ru")
        #expect(items.contains(.translationLanguage(selected: "ru")))

        guard let cleanupIndex = items.firstIndex(of: .cleanupModel(selectedModelId: "m")),
              let translationIndex = items.firstIndex(of: .translationLanguage(selected: "ru")),
              let addVocabularyIndex = items.firstIndex(of: .addVocabulary)
        else {
            Issue.record("cleanup-model, translation-language, and add-vocabulary items must all be present: \(items)")
            return
        }
        #expect(translationIndex == cleanupIndex + 1, "translation-language must sit right after cleanup-model")
        #expect(addVocabularyIndex == translationIndex + 1, "add-vocabulary must directly follow translation-language")
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
