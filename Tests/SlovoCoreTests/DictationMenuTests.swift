import Testing

import SlovoCore

// The dropdown's ordered top-level items, its dynamic "Hold <key> to talk" hint,
// and the availability-driven cleanup block, verified without a running status bar.
@Suite("Dictation menu model")
struct DictationMenuTests {
    private func items(
        availability: CleanupAvailability,
        mute: Bool = true,
        update: UpdateIndication = .idle,
        model: String = "m",
        translate: String = "en",
        trigger: HotkeyTrigger = .fn
    ) -> [DictationMenuItem] {
        DictationMenu.items(
            trigger: trigger,
            selectedModelId: model,
            mutesSystemAudioWhileDictating: mute,
            translationLanguage: translate,
            cleanupAvailability: availability,
            update: update
        )
    }

    private func hasCleanupToggle(_ list: [DictationMenuItem]) -> Bool {
        list.contains { if case .cleanupToggle = $0 { return true }; return false }
    }

    private func hasTranslationLanguage(_ list: [DictationMenuItem]) -> Bool {
        list.contains { if case .translationLanguage = $0 { return true }; return false }
    }

    private func hasCleanupModel(_ list: [DictationMenuItem]) -> Bool {
        list.contains { if case .cleanupModel = $0 { return true }; return false }
    }

    /// With a key and cleanup on, the dropdown appears in the fixed order: header
    /// (status, hint), separator, the cleanup block (switch, translate, model — all
    /// active), separator, the vocabulary block (Add Vocabulary + the mute switch),
    /// separator, and the bottom section holding Settings, About, then Quit.
    /// Stated sensitivity: reorder, drop, or misposition any item — or ignore the
    /// `mutesSystemAudioWhileDictating` arg — → the exact sequence mismatches → RED.
    @Test
    func onStateAppearsInSpecOrder() {
        #expect(items(availability: .on, model: "openai/gpt-5.6-luna") == [
            .status("Idle"),
            .hotkeyHint("Hold fn to talk"),
            .separator,
            .cleanupToggle(isOn: true),
            .cleanupModel(selectedModelId: "openai/gpt-5.6-luna", enabled: true),
            .translationLanguage(selected: "en", enabled: true),
            .separator,
            .addVocabulary,
            .muteWhileDictating(isOn: true),
            .separator,
            .settings,
            .about,
            .quit,
        ])
    }

    /// With a key but cleanup toggled off (offByChoice): the switch stays present and
    /// ACTIVE (the way back on), while the translate and model items are present but
    /// read as unavailable (`enabled: false`). The block still holds all three items.
    /// Stated sensitivity: hide the switch, or mark translate/model `enabled: true`
    /// when off → the exact sequence mismatches → RED.
    @Test
    func offByChoiceKeepsTheThreeItemBlockWithTranslateAndModelDisabled() {
        #expect(items(availability: .offByChoice, model: "x") == [
            .status("Idle"),
            .hotkeyHint("Hold fn to talk"),
            .separator,
            .cleanupToggle(isOn: false),
            .cleanupModel(selectedModelId: "x", enabled: false),
            .translationLanguage(selected: "en", enabled: false),
            .separator,
            .addVocabulary,
            .muteWhileDictating(isOn: true),
            .separator,
            .settings,
            .about,
            .quit,
        ])
    }

    /// With NO key (offNoKey): the entire three-item cleanup block is replaced by the
    /// single add-key affordance in the same separator-delimited slot — the switch,
    /// translate, and model items are omitted entirely (not shown disabled), because
    /// with no key there is nothing to configure.
    /// Stated sensitivity: keep any of switch/translate/model in the no-key state, or
    /// drop the add-key item → the exact sequence mismatches → RED.
    @Test
    func offNoKeyReplacesTheWholeBlockWithAddKey() {
        #expect(items(availability: .offNoKey) == [
            .status("Idle"),
            .hotkeyHint("Hold fn to talk"),
            .separator,
            .addOpenRouterKey,
            .separator,
            .addVocabulary,
            .muteWhileDictating(isOn: true),
            .separator,
            .settings,
            .about,
            .quit,
        ])
        // Reinforce the omission independently of exact ordering: none of the three
        // cleanup controls survive in the no-key state, in any associated form.
        let noKey = items(availability: .offNoKey)
        #expect(!hasCleanupToggle(noKey))
        #expect(!hasTranslationLanguage(noKey))
        #expect(!hasCleanupModel(noKey))
    }

    /// The cleanup block is one separator-delimited group: with a key it is exactly
    /// `[switch, model, translate]` between two separators, in that order (matching the
    /// Settings pane's Cleanup section); with no key it is exactly `[add-key]` between
    /// two separators.
    /// Stated sensitivity: reorder the block (e.g. swap model/translate back), drop its
    /// bounding separators, or leak a neighbouring item into it → the neighbour/bound
    /// asserts redden.
    @Test
    func cleanupBlockIsSeparatorDelimited() {
        for availability in [CleanupAvailability.on, .offByChoice] {
            let list = items(availability: availability, model: "m", translate: "en")
            guard let toggleIndex = list.firstIndex(of: .cleanupToggle(isOn: availability.isOn)) else {
                Issue.record("cleanup toggle missing for \(availability): \(list)")
                continue
            }
            #expect(list[toggleIndex - 1] == .separator, "block must open with a separator for \(availability)")
            #expect(list[toggleIndex + 1] == .cleanupModel(selectedModelId: "m", enabled: availability.isOn))
            #expect(list[toggleIndex + 2] == .translationLanguage(selected: "en", enabled: availability.isOn))
            #expect(list[toggleIndex + 3] == .separator, "block must close with a separator for \(availability)")
        }
        let noKey = items(availability: .offNoKey)
        guard let addKeyIndex = noKey.firstIndex(of: .addOpenRouterKey) else {
            Issue.record("add-key missing in no-key state: \(noKey)")
            return
        }
        #expect(noKey[addKeyIndex - 1] == .separator, "add-key must open its section")
        #expect(noKey[addKeyIndex + 1] == .separator, "add-key must be alone in its separator-delimited slot")
    }

    /// Item A — the model selector reads as unavailable whenever cleanup is off with a
    /// key present (offByChoice), active only when cleanup is on; with no key it is
    /// gone (covered by the block swap). Mirrors the translate item.
    /// Stated sensitivity: hardcode `enabled: true` for the model item → the
    /// offByChoice expectation reads enabled → RED.
    @Test
    func modelSelectorIsDisabledWhenCleanupToggledOff() {
        #expect(items(availability: .offByChoice, model: "m").contains(.cleanupModel(selectedModelId: "m", enabled: false)))
        #expect(items(availability: .on, model: "m").contains(.cleanupModel(selectedModelId: "m", enabled: true)))
    }

    /// The cleanup switch is type-narrowed to `isOn`, so an off-and-disabled toggle is
    /// unrepresentable — when shown it is always actionable, and `isOn` only drives the
    /// checkmark: checked in `on`, unchecked (but still actionable) in `offByChoice`.
    /// Stated sensitivity: hardcode the emitter's `isOn` (e.g. always `true`) → the
    /// `offByChoice` `isOn: false` expectation reddens; pass the wrong on-state → the
    /// `.on` `isOn: true` expectation reddens.
    @Test
    func cleanupToggleReflectsOnStateAndIsAlwaysActionable() {
        #expect(items(availability: .on).contains(.cleanupToggle(isOn: true)))
        #expect(items(availability: .offByChoice).contains(.cleanupToggle(isOn: false)))
    }

    /// The translate submenu reads as unavailable in offByChoice and is ABSENT with no
    /// key (a translate hold cannot run without cleanup, and with no key there is no
    /// block at all); enabled only when cleanup is on.
    /// Stated sensitivity: hardcode `enabled: true` for translate → the offByChoice
    /// expectation reddens; keep translate in the no-key state → the absence reddens.
    @Test
    func translateSubmenuDisabledInOffByChoiceAbsentInOffNoKey() {
        #expect(items(availability: .offByChoice, translate: "en").contains(.translationLanguage(selected: "en", enabled: false)))
        #expect(items(availability: .on, translate: "en").contains(.translationLanguage(selected: "en", enabled: true)))
        #expect(!hasTranslationLanguage(items(availability: .offNoKey, translate: "en")))
    }

    /// The mute switch lives in the vocabulary block adjacent to Add Vocabulary — NOT
    /// in the cleanup block — and is availability-INDEPENDENT: present in the same slot
    /// in every availability state (mute works regardless of cleanup). The block is
    /// `[separator, Add Vocabulary, mute, separator]`.
    /// Stated sensitivity: move mute into the cleanup block, couple it to availability
    /// (drop it in offNoKey), or detach it from Add Vocabulary → RED.
    @Test
    func muteLivesInTheVocabularyBlockInAllStates() {
        for availability in [CleanupAvailability.on, .offByChoice, .offNoKey] {
            let list = items(availability: availability, mute: true)
            guard let vocabIndex = list.firstIndex(of: .addVocabulary),
                  let muteIndex = list.firstIndex(of: .muteWhileDictating(isOn: true))
            else {
                Issue.record("vocab/mute missing for \(availability): \(list)")
                continue
            }
            #expect(muteIndex == vocabIndex + 1, "mute sits right after Add Vocabulary for \(availability)")
            #expect(list[vocabIndex - 1] == .separator, "the vocabulary block opens with a separator for \(availability)")
            #expect(list[muteIndex + 1] == .separator, "the vocabulary block closes right after mute for \(availability)")
        }
    }

    /// AC9: passing the mute flag as `false` yields `.muteWhileDictating(isOn: false)`
    /// in its pinned vocabulary-block slot — proving the item reflects the argument.
    /// Stated sensitivity: hard-code the item's `isOn`, or move it out of the
    /// after-Add-Vocabulary slot → RED.
    @Test
    func muteWhileDictatingReflectsDisabledFlag() {
        let list = items(availability: .on, mute: false)
        guard let vocabIndex = list.firstIndex(of: .addVocabulary) else {
            Issue.record("Add Vocabulary missing: \(list)")
            return
        }
        #expect(list[vocabIndex + 1] == .muteWhileDictating(isOn: false), "mute reflects the flag in its pinned slot")
    }

    /// The bottom section is exactly `[separator, Settings, About, Quit]` — Settings
    /// above About, About directly above Quit, all under one separator, Quit last — in
    /// EVERY availability and update state.
    /// Stated sensitivity: reorder Settings/About/Quit, insert a separator between
    /// them, or leave Settings/About in an old slot → the suffix mismatches → RED.
    @Test
    func bottomSectionIsSeparatorSettingsAboutQuitInAllStates() {
        let updates: [UpdateIndication] = [.idle, .downloading(version: "0.14.0"), .ready(version: "0.14.0")]
        for availability in [CleanupAvailability.on, .offByChoice, .offNoKey] {
            for update in updates {
                let list = items(availability: availability, update: update)
                #expect(Array(list.suffix(4)) == [.separator, .settings, .about, .quit], "\(availability)/\(update): \(list)")
            }
        }
    }

    /// Quit is the isolated last item.
    /// Stated sensitivity: append anything after `.quit` or drop `.quit` → RED.
    @Test
    func quitIsTheLastItem() {
        #expect(items(availability: .on).last == .quit)
    }

    /// No two separators are ever adjacent — none of the block moves may leave a
    /// doubled divider or an empty section, in any availability state.
    /// Stated sensitivity: drop an item between two separators (leaving them adjacent)
    /// → RED.
    @Test
    func noDoubledSeparatorsInAnyState() {
        for availability in [CleanupAvailability.on, .offByChoice, .offNoKey] {
            let list = items(availability: availability)
            for (first, second) in zip(list, list.dropFirst()) {
                #expect(!(first == .separator && second == .separator), "doubled separator in \(availability): \(list)")
            }
        }
    }

    /// The hint uses the trigger's display name, not its wire value.
    /// Stated sensitivity: build the hint from `trigger.rawValue` (or a fixed "fn")
    /// → "Hold right-command to talk" ≠ "Hold Right ⌘ to talk" → RED.
    @Test
    func hotkeyHintUsesTriggerDisplayName() {
        #expect(items(availability: .on, trigger: .rightCommand).contains(.hotkeyHint("Hold Right ⌘ to talk")))
    }

    /// The cleanup-model item carries the selected id so the builder checks the right
    /// catalog row.
    /// Stated sensitivity: hard-code or drop the id → the wrong row would be checked → RED.
    @Test
    func cleanupModelItemCarriesSelectedId() {
        #expect(items(availability: .on, model: "anthropic/claude-haiku-4.5")
            .contains(.cleanupModel(selectedModelId: "anthropic/claude-haiku-4.5", enabled: true)))
    }

    /// While an update downloads, the status header gains EXACTLY ONE extra disabled
    /// line — `.updateDownloading` — at index 2, directly after the hint and before
    /// the first separator, no separator of its own; everything else stays put.
    /// Stated sensitivity: ignore the `update` argument, render the wrong case, place
    /// the line at any other index, or fence it with a separator → RED.
    @Test
    func downloadingUpdateInsertsOneHeaderLine() {
        #expect(items(availability: .on, update: .downloading(version: "0.14.0")) == [
            .status("Idle"),
            .hotkeyHint("Hold fn to talk"),
            .updateDownloading(version: "0.14.0"),
            .separator,
            .cleanupToggle(isOn: true),
            .cleanupModel(selectedModelId: "m", enabled: true),
            .translationLanguage(selected: "en", enabled: true),
            .separator,
            .addVocabulary,
            .muteWhileDictating(isOn: true),
            .separator,
            .settings,
            .about,
            .quit,
        ])
    }

    /// Once validated, the same header slot (index 2) holds the hybrid `.updateReady`
    /// row instead — again exactly one extra element, no extra separator.
    /// Stated sensitivity: keep showing `.updateDownloading`, move the row out of the
    /// header slot, or add a separator around it → RED.
    @Test
    func readyUpdateHoldsTheSameHeaderSlot() {
        #expect(items(availability: .on, update: .ready(version: "0.14.0")) == [
            .status("Idle"),
            .hotkeyHint("Hold fn to talk"),
            .updateReady(version: "0.14.0"),
            .separator,
            .cleanupToggle(isOn: true),
            .cleanupModel(selectedModelId: "m", enabled: true),
            .translationLanguage(selected: "en", enabled: true),
            .separator,
            .addVocabulary,
            .muteWhileDictating(isOn: true),
            .separator,
            .settings,
            .about,
            .quit,
        ])
    }
}
