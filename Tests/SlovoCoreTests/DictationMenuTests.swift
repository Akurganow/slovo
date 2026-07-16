import Testing

import SlovoCore

// The dropdown's ordered top-level items and its dynamic "Hold <key> to talk"
// hint, verified without a running status bar.
@Suite("Dictation menu model")
struct DictationMenuTests {
    /// AC9: the items appear in the fixed spec order: title, status, hotkey hint,
    /// separator, cleanup-model, add-vocabulary, mute-while-dictating, separator,
    /// settings, quit. The mute switch sits AFTER Add Vocabulary and BEFORE the
    /// trailing separator, carrying the live flag.
    /// Stated sensitivity: reorder, drop, or misposition any item — or ignore the
    /// `mutesSystemAudioWhileDictating` arg — → the exact sequence mismatches → RED.
    @Test
    func itemsAppearInSpecOrder() {
        let items = DictationMenu.items(
            trigger: .fn,
            selectedModelId: "openai/gpt-5.6-luna",
            mutesSystemAudioWhileDictating: true
        )
        #expect(items == [
            .title("Slovo"),
            .status("Idle"),
            .hotkeyHint("Hold fn to talk"),
            .separator,
            .cleanupModel(selectedModelId: "openai/gpt-5.6-luna"),
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
            mutesSystemAudioWhileDictating: false
        )
        #expect(items == [
            .title("Slovo"),
            .status("Idle"),
            .hotkeyHint("Hold fn to talk"),
            .separator,
            .cleanupModel(selectedModelId: "x"),
            .addVocabulary,
            .muteWhileDictating(isOn: false),
            .separator,
            .settings,
            .quit,
        ])
    }

    /// The hint uses the trigger's display name, not its wire value.
    /// Stated sensitivity: build the hint from `trigger.rawValue` (or a fixed "fn")
    /// → "Hold right-command to talk" ≠ "Hold Right ⌘ to talk" → RED.
    @Test
    func hotkeyHintUsesTriggerDisplayName() {
        let items = DictationMenu.items(trigger: .rightCommand, selectedModelId: "x", mutesSystemAudioWhileDictating: true)
        #expect(items.contains(.hotkeyHint("Hold Right ⌘ to talk")))
    }

    /// The cleanup-model item carries the selected id so the builder can check the
    /// right catalog row.
    /// Stated sensitivity: hard-code or drop the id → the wrong row would be
    /// checked → RED.
    @Test
    func cleanupModelItemCarriesSelectedId() {
        let items = DictationMenu.items(trigger: .fn, selectedModelId: "anthropic/claude-haiku-4.5", mutesSystemAudioWhileDictating: true)
        #expect(items.contains(.cleanupModel(selectedModelId: "anthropic/claude-haiku-4.5")))
    }
}
