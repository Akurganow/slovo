import Testing

import SlovoCore

// The dropdown's ordered top-level items, its single status line carrying the
// dynamic "Hold <key> to talk" hint when idle, and the availability-driven cleanup
// block, verified without a running status bar.
@Suite("Dictation menu model")
struct DictationMenuTests {
    /// The exact remedy copy the conflict notice must carry, pinned verbatim.
    private let fnConflictCopy =
        "fn also triggers a macOS action — set “Press 🌐 key to” to “Do Nothing” in System Settings ▸ Keyboard"

    private func items(
        availability: CleanupAvailability,
        mute: Bool = true,
        soundCues: Bool = true,
        model: String = "m",
        translate: String = "en",
        trigger: HotkeyTrigger = .fn,
        fnAssigned: Bool = false
    ) -> [DictationMenuItem] {
        DictationMenu.items(
            trigger: trigger,
            cleanup: DictationMenuCleanupConfiguration(
                selectedModelId: model,
                translationLanguage: translate,
                availability: availability
            ),
            mutesSystemAudioWhileDictating: mute,
            playsDictationSoundCues: soundCues,
            isFnKeySystemAssigned: fnAssigned
        )
    }

    private func fnConflictNoticeCount(_ list: [DictationMenuItem]) -> Int {
        list.filter { if case .fnConflictNotice = $0 { return true }; return false }.count
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
    /// (the status line carrying the hold-to-talk hint), separator, the cleanup
    /// block (switch, model, translate — all active), separator, the vocabulary
    /// block (Add Vocabulary + the adjacent Mute and Sound Cues switches), separator,
    /// and the bottom section holding Settings, About, then Quit.
    /// Stated sensitivity: reorder, drop, or misposition any item — or ignore either
    /// live-switch argument — → the exact sequence mismatches → RED.
    @Test
    func onStateAppearsInSpecOrder() {
        #expect(items(availability: .on, model: "openai/gpt-5.6-luna") == [
            .status("Hold fn to talk"),
            .separator,
            .cleanupToggle(isOn: true),
            .cleanupModel(selectedModelId: "openai/gpt-5.6-luna", enabled: true),
            .translationLanguage(selected: "en", enabled: true),
            .separator,
            .addVocabulary,
            .muteWhileDictating(isOn: true),
            .soundCues(isOn: true),
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
            .status("Hold fn to talk"),
            .separator,
            .cleanupToggle(isOn: false),
            .cleanupModel(selectedModelId: "x", enabled: false),
            .translationLanguage(selected: "en", enabled: false),
            .separator,
            .addVocabulary,
            .muteWhileDictating(isOn: true),
            .soundCues(isOn: true),
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
            .status("Hold fn to talk"),
            .separator,
            .addOpenRouterKey,
            .separator,
            .addVocabulary,
            .muteWhileDictating(isOn: true),
            .soundCues(isOn: true),
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

    /// The live switches live in the vocabulary block — NOT in the cleanup block —
    /// and are availability-INDEPENDENT. Sound Cues sits directly after Mute in every
    /// availability state. The block is exactly
    /// `[separator, Add Vocabulary, Mute, Sound Cues, separator]`.
    /// Stated sensitivity: move either switch into the cleanup block, couple either to
    /// availability, detach Mute from Add Vocabulary, or detach Sound Cues from Mute → RED.
    @Test
    func muteAndSoundCuesLiveTogetherInTheVocabularyBlockInAllStates() {
        for availability in [CleanupAvailability.on, .offByChoice, .offNoKey] {
            let list = items(availability: availability, mute: true)
            guard let vocabIndex = list.firstIndex(of: .addVocabulary),
                  let muteIndex = list.firstIndex(of: .muteWhileDictating(isOn: true)),
                  let soundCuesIndex = list.firstIndex(of: .soundCues(isOn: true))
            else {
                Issue.record("vocab/mute/sound cues missing for \(availability): \(list)")
                continue
            }
            #expect(muteIndex == vocabIndex + 1, "mute sits right after Add Vocabulary for \(availability)")
            #expect(soundCuesIndex == muteIndex + 1, "Sound Cues sits right after Mute for \(availability)")
            #expect(list[vocabIndex - 1] == .separator, "the vocabulary block opens with a separator for \(availability)")
            #expect(list[soundCuesIndex + 1] == .separator,
                    "the vocabulary block closes right after Sound Cues for \(availability)")
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

    /// Passing the cue flag as `false` yields `.soundCues(isOn: false)` directly
    /// after Mute in every cleanup state. This independently proves the row is not
    /// hard-coded on and cannot drift away from its required neighbour.
    /// Stated sensitivity: ignore the flag, omit the item in an off state, or insert
    /// any item between Mute and Sound Cues → RED.
    @Test
    func soundCuesReflectsDisabledFlagNextToMuteInAllStates() {
        for availability in [CleanupAvailability.on, .offByChoice, .offNoKey] {
            let list = items(availability: availability, soundCues: false)
            guard let muteIndex = list.firstIndex(of: .muteWhileDictating(isOn: true)) else {
                Issue.record("Mute missing for \(availability): \(list)")
                continue
            }
            #expect(list[muteIndex + 1] == .soundCues(isOn: false),
                    "Sound Cues reflects its flag directly after Mute for \(availability)")
        }
    }

    /// The bottom section is exactly `[separator, Settings, About, Quit]` — Settings
    /// above About, About directly above Quit, all under one separator, Quit last — in
    /// EVERY availability state.
    /// Stated sensitivity: reorder Settings/About/Quit, insert a separator between
    /// them, or leave Settings/About in an old slot → the suffix mismatches → RED.
    @Test
    func bottomSectionIsSeparatorSettingsAboutQuitInAllStates() {
        for availability in [CleanupAvailability.on, .offByChoice, .offNoKey] {
            let list = items(availability: availability)
            #expect(Array(list.suffix(4)) == [.separator, .settings, .about, .quit], "\(availability): \(list)")
        }
    }

    /// Quit is the isolated last item.
    /// Stated sensitivity: append anything after `.quit` or drop `.quit` → RED.
    @Test
    func quitIsTheLastItem() {
        #expect(items(availability: .on).last == .quit)
    }

    /// No two separators are ever adjacent — none of the block moves may leave a
    /// doubled divider or an empty section, in any availability state, with or
    /// without the fn conflict notice in the header.
    /// Stated sensitivity: drop an item between two separators (leaving them adjacent)
    /// → RED.
    @Test
    func noDoubledSeparatorsInAnyState() {
        for availability in [CleanupAvailability.on, .offByChoice, .offNoKey] {
            for fnAssigned in [false, true] {
                let list = items(availability: availability, fnAssigned: fnAssigned)
                for (first, second) in zip(list, list.dropFirst()) {
                    #expect(!(first == .separator && second == .separator),
                            "doubled separator in \(availability), fnAssigned=\(fnAssigned): \(list)")
                }
            }
        }
    }

    // MARK: - fn conflict notice: the header warns when the fn TRIGGER collides
    // with a macOS system assignment of the fn key — and only then.

    /// With the fn trigger and fn assigned to a macOS action, the notice appears
    /// EXACTLY once, directly after the status line, carrying the exact remedy copy.
    /// Stated sensitivity: drop the emission, change the copy, emit it twice, or
    /// move it out of the after-status slot → RED.
    @Test
    func fnConflictNoticeAppearsOnceDirectlyAfterStatusLine() {
        let list = items(availability: .on, fnAssigned: true)
        #expect(fnConflictNoticeCount(list) == 1)
        guard let statusIndex = list.firstIndex(of: .status("Hold fn to talk")) else {
            Issue.record("status line missing: \(list)")
            return
        }
        #expect(list[statusIndex + 1] == .fnConflictNotice(fnConflictCopy))
    }

    /// With fn NOT system-assigned the notice is absent — the menu never warns
    /// about a conflict that does not exist.
    /// Stated sensitivity: emit the notice unconditionally (ignore the assigned
    /// flag) → RED.
    @Test
    func fnConflictNoticeAbsentWhenFnNotSystemAssigned() {
        #expect(fnConflictNoticeCount(items(availability: .on, fnAssigned: false)) == 0)
    }

    /// The notice is fn-trigger-ONLY: with the `.rightOption` trigger the fn key's
    /// system assignment is irrelevant, even when assigned.
    /// Stated sensitivity: drop the trigger gate (warn on the assigned flag alone)
    /// → RED.
    @Test
    func fnConflictNoticeAbsentForNonFnTrigger() {
        #expect(fnConflictNoticeCount(items(availability: .on, trigger: .rightOption, fnAssigned: true)) == 0)
    }

    /// The idle status line IS the hold-to-talk hint, built from the trigger's
    /// display name (not its wire value), and the model owns the copy:
    /// `idleStatusLine(trigger:)` is the single source for both the seeded item
    /// and the app delegate's idle restores.
    /// Stated sensitivity: build the line from `trigger.rawValue` (or a fixed "fn")
    /// → "Hold right-command to talk" ≠ "Hold Right ⌘ to talk" → RED; desync the
    /// helper from the seeded item → the contains/equality pair mismatches → RED.
    @Test
    func statusLineUsesTriggerDisplayName() {
        #expect(items(availability: .on, trigger: .rightCommand).contains(.status("Hold Right ⌘ to talk")))
        #expect(items(availability: .on, trigger: .rightOption).contains(.status("Hold Right ⌥ to talk")))
        #expect(items(availability: .on, trigger: .leftOption).contains(.status("Hold Left ⌥ to talk")))
        #expect(DictationMenu.idleStatusLine(trigger: .rightCommand) == "Hold Right ⌘ to talk")
    }

    /// The cleanup-model item carries the selected id so the builder checks the right
    /// catalog row.
    /// Stated sensitivity: hard-code or drop the id → the wrong row would be checked → RED.
    @Test
    func cleanupModelItemCarriesSelectedId() {
        #expect(items(availability: .on, model: "anthropic/claude-haiku-4.5")
            .contains(.cleanupModel(selectedModelId: "anthropic/claude-haiku-4.5", enabled: true)))
    }
}
