import Testing

import SlovoCore

// The dropdown's ordered top-level items and its dynamic "Hold <key> to talk"
// hint, verified without a running status bar.
@Suite("Dictation menu model")
struct DictationMenuTests {
    /// The items appear in the fixed spec order: title, status, hotkey hint,
    /// separator, cleanup-model, add-vocabulary, separator, settings, quit.
    /// Stated sensitivity: reorder or drop any item → the exact sequence mismatches
    /// → RED.
    @Test
    func itemsAppearInSpecOrder() {
        let items = DictationMenu.items(trigger: .fn, selectedModelId: "openai/gpt-5.4-nano")
        #expect(items == [
            .title("Slovo"),
            .status("Idle"),
            .hotkeyHint("Hold fn to talk"),
            .separator,
            .cleanupModel(selectedModelId: "openai/gpt-5.4-nano"),
            .addVocabulary,
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
        let items = DictationMenu.items(trigger: .rightCommand, selectedModelId: "x")
        #expect(items.contains(.hotkeyHint("Hold Right ⌘ to talk")))
    }

    /// The cleanup-model item carries the selected id so the builder can check the
    /// right catalog row.
    /// Stated sensitivity: hard-code or drop the id → the wrong row would be
    /// checked → RED.
    @Test
    func cleanupModelItemCarriesSelectedId() {
        let items = DictationMenu.items(trigger: .fn, selectedModelId: "anthropic/claude-haiku-4.5")
        #expect(items.contains(.cleanupModel(selectedModelId: "anthropic/claude-haiku-4.5")))
    }
}
