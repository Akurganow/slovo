import Testing

import SlovoCore

// The dropdown's ordered top-level items and its dynamic "Hold <key> to talk"
// hint, verified without a running status bar.
@Suite("Dictation menu model")
struct DictationMenuTests {
    /// The items appear in the fixed spec order, grouped by role: the header
    /// (status, hotkey hint — no separate "Slovo" title item, since it never read
    /// as clickable), separator, live switches (cleanup-model,
    /// translation-language, mute-while-dictating), separator, window openers
    /// (add-vocabulary, settings), separator, quit, then About — the trailing
    /// group's last entry, right after Quit.
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
            .status("Idle"),
            .hotkeyHint("Hold fn to talk"),
            .separator,
            .cleanupModel(selectedModelId: "openai/gpt-5.6-luna"),
            .translationLanguage(selected: "en"),
            .muteWhileDictating(isOn: true),
            .separator,
            .addVocabulary,
            .settings,
            .separator,
            .quit,
            .about,
        ])
    }

    /// About is the very last entry in the dropdown, directly after Quit, in the
    /// same trailing group (no separator between them).
    /// Stated sensitivity: move `.about` out of the last slot (e.g. ahead of Quit,
    /// or back to the top) → `quitPrecedesAbout` reddens on the ordering assert;
    /// drop `.about` entirely → `items.last == .about` reddens.
    @Test
    func aboutIsTheLastItem() {
        let items = DictationMenu.items(
            trigger: .fn,
            selectedModelId: "m",
            mutesSystemAudioWhileDictating: true,
            translationLanguage: "en"
        )
        #expect(items.last == .about)
    }

    /// Quit directly precedes About — they share the trailing group with no
    /// separator between them.
    /// Stated sensitivity: swap the two (About above Quit) → the index assert
    /// reddens; insert a `.separator` between them → `quitIndex + 1` no longer
    /// equals `aboutIndex` → RED.
    @Test
    func quitPrecedesAbout() {
        let items = DictationMenu.items(
            trigger: .fn,
            selectedModelId: "m",
            mutesSystemAudioWhileDictating: true,
            translationLanguage: "en"
        )
        guard let quitIndex = items.firstIndex(of: .quit),
              let aboutIndex = items.firstIndex(of: .about)
        else {
            Issue.record("quit and about items must both be present: \(items)")
            return
        }
        #expect(aboutIndex == quitIndex + 1, "about must directly follow quit with no separator")
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
            .status("Idle"),
            .hotkeyHint("Hold fn to talk"),
            .separator,
            .cleanupModel(selectedModelId: "x"),
            .translationLanguage(selected: "en"),
            .muteWhileDictating(isOn: false),
            .separator,
            .addVocabulary,
            .settings,
            .separator,
            .quit,
            .about,
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
