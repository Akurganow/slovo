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
        translateTrigger: HotkeyTrigger = .control,
        translateIsAdditional: Bool = true,
        fnAssigned: Bool = false,
        statusLine: String = "Hold fn to talk"
    ) -> [DictationMenuItem] {
        DictationMenu.items(
            hotkeys: HotkeyConfiguration(
                main: trigger,
                translate: translateTrigger,
                translateIsAdditional: translateIsAdditional
            ),
            cleanup: DictationMenuCleanupConfiguration(
                selectedModelId: model,
                translationLanguage: translate,
                availability: availability
            ),
            mutesSystemAudioWhileDictating: mute,
            playsDictationSoundCues: soundCues,
            rows: DictationMenuRows(statusLine: statusLine, isFnKeySystemAssigned: fnAssigned)
        )
    }

    private func fnConflictNoticeCount(_ list: [DictationMenuItem]) -> Int {
        list.filter { if case .fnConflictNotice = $0 { return true }; return false }.count
    }

    /// With a key and cleanup on, the dropdown appears in the fixed order: header
    /// (the status line carrying the hold-to-talk hint), separator, the cleanup
    /// block (switch, model, translate — all active), separator, the vocabulary
    /// block (Add Vocabulary, the Microphone submenu, then the Mute and Sound Cues
    /// switches), separator,
    /// and the bottom section holding Settings, About, then Quit.
    /// Stated sensitivity: reorder, drop, or misposition any item — or ignore either
    /// live-switch argument — → the exact sequence mismatches → RED.
    @Test
    func onStateAppearsInSpecOrder() {
        #expect(items(availability: .on, model: "openai/gpt-6-luna", translate: "de") == [
            .status("Hold fn to talk"),
            .translateHint("Add ⌃ to translate"),
            .separator,
            .cleanupToggle(isOn: true),
            .cleanupModel(selectedModelId: "openai/gpt-6-luna", enabled: true),
            .translationLanguage(selected: "de", enabled: true),
            .separator,
            .addVocabulary,
            .microphone,
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
            .translateHint("Add ⌃ to translate"),
            .separator,
            .cleanupToggle(isOn: false),
            .cleanupModel(selectedModelId: "x", enabled: false),
            .translationLanguage(selected: "en", enabled: false),
            .separator,
            .addVocabulary,
            .microphone,
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
            .translateHint("Add ⌃ to translate"),
            .separator,
            .addOpenRouterKey,
            .separator,
            .addVocabulary,
            .microphone,
            .muteWhileDictating(isOn: true),
            .soundCues(isOn: true),
            .separator,
            .settings,
            .about,
            .quit,
        ])
    }

    /// AC9: passing the mute flag as `false` yields `.muteWhileDictating(isOn: false)`
    /// in its pinned vocabulary-block slot — proving the item reflects the argument.
    /// Stated sensitivity: hard-code the item's `isOn`, or move it out of the
    /// after-Microphone slot → RED.
    @Test
    func muteWhileDictatingReflectsDisabledFlag() {
        let list = items(availability: .on, mute: false)
        guard let microphoneIndex = list.firstIndex(of: .microphone) else {
            Issue.record("the Microphone submenu missing: \(list)")
            return
        }
        #expect(list[microphoneIndex + 1] == .muteWhileDictating(isOn: false), "mute reflects the flag in its pinned slot")
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

    /// The notice is fn-trigger-ONLY: with the `.rightOption` trigger the fn key's
    /// system assignment is irrelevant, even when assigned.
    /// Stated sensitivity: drop the trigger gate (warn on the assigned flag alone)
    /// → RED.
    @Test
    func fnConflictNoticeAbsentForNonFnTrigger() {
        #expect(fnConflictNoticeCount(items(availability: .on, trigger: .rightOption, fnAssigned: true)) == 0)
    }

    /// A rebuild must keep the line the user is looking at: the status row is seeded
    /// with the line the app passes, never re-derived from the trigger.
    /// Stated sensitivity: seed the status row with the idle hint instead of
    /// `rows.statusLine` → RED; the build is the only writer on a rebuild, so this
    /// pins the status-line reset itself.
    @Test
    func statusRowCarriesTheCurrentLine() {
        #expect(items(availability: .on, statusLine: "Recording").first == .status("Recording"))
    }

    /// The translate hint is the header's second idle line, and it names the
    /// configured translate key and its mode: "Add" while the key rides on top of a
    /// main-key hold, "Hold" while it dictates on its own (matching the main key's
    /// line). It is built from the key's display name, never its wire value.
    /// Stated sensitivity: hardcode either the key (⌃) or the mode word, build the
    /// line from `rawValue` ("Add left-shift to translate"), or swap the two mode
    /// words → the exact-equality `#expect` mismatches → RED.
    @Test
    func translateHintNamesTheConfiguredKeyAndMode() {
        #expect(items(availability: .on).contains(.translateHint("Add ⌃ to translate")))
        #expect(items(availability: .on, translateTrigger: .leftShift)
            .contains(.translateHint("Add Left ⇧ to translate")))
        #expect(items(availability: .on, translateTrigger: .leftShift, translateIsAdditional: false)
            .contains(.translateHint("Hold Left ⇧ to translate")))
        // Main-key-independent: the additional line names the translate key alone.
        #expect(items(availability: .on, trigger: .rightOption, translateTrigger: .fn)
            .contains(.translateHint("Add fn to translate")))
    }

    /// The fn-conflict notice follows the fn KEY into either role: a translate key on
    /// fn collides with the macOS assignment exactly as a main key on fn does.
    /// Stated sensitivity: gate the notice on `hotkeys.main == .fn` alone → the
    /// translate-on-fn case reports 0 notices → RED.
    @Test
    func fnConflictNoticeFollowsTheFnKeyIntoTheTranslateRole() {
        let list = items(availability: .on, trigger: .rightOption, translateTrigger: .fn, fnAssigned: true)
        #expect(fnConflictNoticeCount(list) == 1)
        #expect(list.contains(.fnConflictNotice(fnConflictCopy)))
        // Still gated on the system assignment: no assignment, no notice.
        #expect(fnConflictNoticeCount(
            items(availability: .on, trigger: .rightOption, translateTrigger: .fn, fnAssigned: false)
        ) == 0)
    }
}
