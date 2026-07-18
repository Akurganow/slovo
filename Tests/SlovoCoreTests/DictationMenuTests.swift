import Testing

import SlovoCore

// The dropdown's ordered top-level items and its dynamic "Hold <key> to talk"
// hint, verified without a running status bar.
@Suite("Dictation menu model")
struct DictationMenuTests {
    /// The items appear in the fixed spec order, grouped by role: the header
    /// (status, hotkey hint — no separate "Slovo" title item, since it never read
    /// as clickable), separator, About in its own group, separator, live switches
    /// (cleanup-model, translation-language, mute-while-dictating), separator,
    /// window openers (add-vocabulary, settings), separator, quit isolated last.
    /// Stated sensitivity: reorder, drop, or misposition any item — or ignore the
    /// `mutesSystemAudioWhileDictating` arg — → the exact sequence mismatches → RED.
    @Test
    func itemsAppearInSpecOrder() {
        let items = DictationMenu.items(
            trigger: .fn,
            selectedModelId: "openai/gpt-5.6-luna",
            mutesSystemAudioWhileDictating: true,
            translationLanguage: "en",
            update: .hidden
        )
        #expect(items == [
            .status("Idle"),
            .hotkeyHint("Hold fn to talk"),
            .separator,
            .about,
            .separator,
            .cleanupModel(selectedModelId: "openai/gpt-5.6-luna"),
            .translationLanguage(selected: "en"),
            .muteWhileDictating(isOn: true),
            .separator,
            .addVocabulary,
            .settings,
            .separator,
            .quit,
        ])
    }

    /// Quit closes the dropdown as the isolated last item.
    /// Stated sensitivity: append anything after `.quit` (as About once was) or
    /// drop `.quit` → `items.last == .quit` reddens.
    @Test
    func quitIsTheLastItem() {
        let items = DictationMenu.items(
            trigger: .fn,
            selectedModelId: "m",
            mutesSystemAudioWhileDictating: true,
            translationLanguage: "en",
            update: .hidden
        )
        #expect(items.last == .quit)
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
            translationLanguage: "en",
            update: .hidden
        )
        #expect(items == [
            .status("Idle"),
            .hotkeyHint("Hold fn to talk"),
            .separator,
            .about,
            .separator,
            .cleanupModel(selectedModelId: "x"),
            .translationLanguage(selected: "en"),
            .muteWhileDictating(isOn: false),
            .separator,
            .addVocabulary,
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
        let items = DictationMenu.items(trigger: .fn, selectedModelId: "m", mutesSystemAudioWhileDictating: true, translationLanguage: "ru", update: .hidden)
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
        let items = DictationMenu.items(
            trigger: .rightCommand,
            selectedModelId: "x",
            mutesSystemAudioWhileDictating: true,
            translationLanguage: "en",
            update: .hidden
        )
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
            translationLanguage: "en",
            update: .hidden
        )
        #expect(items.contains(.cleanupModel(selectedModelId: "anthropic/claude-haiku-4.5")))
    }

    /// While an update downloads, the status header gains EXACTLY ONE extra
    /// disabled line — `.updateDownloading` — at index 2: directly after the
    /// hotkey hint, directly before the first separator, no separator of its
    /// own; everything else stays exactly today's menu.
    /// Stated sensitivity: ignore the `update` argument (render nothing), render
    /// the wrong case, place the line at any other index, or fence it with an
    /// extra separator → the exact sequence mismatches → RED.
    @Test
    func downloadingUpdateInsertsOneHeaderLine() {
        let items = DictationMenu.items(
            trigger: .fn,
            selectedModelId: "m",
            mutesSystemAudioWhileDictating: true,
            translationLanguage: "en",
            update: .downloading(version: "0.14.0")
        )
        #expect(items == [
            .status("Idle"),
            .hotkeyHint("Hold fn to talk"),
            .updateDownloading(version: "0.14.0"),
            .separator,
            .about,
            .separator,
            .cleanupModel(selectedModelId: "m"),
            .translationLanguage(selected: "en"),
            .muteWhileDictating(isOn: true),
            .separator,
            .addVocabulary,
            .settings,
            .separator,
            .quit,
        ])
    }

    /// Once an update is downloaded and validated, the same header slot (index
    /// 2) holds the hybrid `.updateReady` row instead — again exactly one extra
    /// element over today's menu, with no extra separator.
    /// Stated sensitivity: ignore the `update` argument, keep showing
    /// `.updateDownloading`, move the row out of the header slot, or add a
    /// separator around it → the exact sequence mismatches → RED.
    @Test
    func readyUpdateHoldsTheSameHeaderSlot() {
        let items = DictationMenu.items(
            trigger: .fn,
            selectedModelId: "m",
            mutesSystemAudioWhileDictating: true,
            translationLanguage: "en",
            update: .ready(version: "0.14.0")
        )
        #expect(items == [
            .status("Idle"),
            .hotkeyHint("Hold fn to talk"),
            .updateReady(version: "0.14.0"),
            .separator,
            .about,
            .separator,
            .cleanupModel(selectedModelId: "m"),
            .translationLanguage(selected: "en"),
            .muteWhileDictating(isOn: true),
            .separator,
            .addVocabulary,
            .settings,
            .separator,
            .quit,
        ])
    }

    /// About is the first interactive item in its own group: it directly follows
    /// the FIRST separator (the one closing the disabled status header) and is
    /// itself followed by a separator, so it reads as its own group — and that
    /// position is invariant across ALL update states (nothing, a downloading
    /// line, or the ready hybrid row in the header). Deliberate grouping
    /// exception per the design spec: in `ready` the header slot holds an
    /// actionable hybrid row, so the "first interactive item" wording holds
    /// outside `ready` — the position pin holds always.
    /// Stated sensitivity: move `.about` anywhere else (into the switches group,
    /// back after Quit) or drop its trailing separator → RED; insert the update
    /// line BELOW the first separator, or fence it with its own separator →
    /// About shifts off the first-separator neighbour slot → RED.
    @Test
    func aboutPositionIsInvariantAcrossUpdateStates() {
        let states: [UpdateIndication] = [.hidden, .downloading(version: "0.14.0"), .ready(version: "0.14.0")]
        for update in states {
            let items = DictationMenu.items(
                trigger: .fn,
                selectedModelId: "m",
                mutesSystemAudioWhileDictating: true,
                translationLanguage: "en",
                update: update
            )
            guard let firstSeparatorIndex = items.firstIndex(of: .separator),
                  let aboutIndex = items.firstIndex(of: .about)
            else {
                Issue.record("separator and about items must both be present for \(update): \(items)")
                continue
            }
            #expect(aboutIndex == firstSeparatorIndex + 1, "about must directly follow the first separator for \(update)")
            #expect(items[aboutIndex + 1] == .separator, "about must sit alone in its own group for \(update)")
        }
    }
}
