/// One top-level entry in the status-menu dropdown, AppKit-free so the item order
/// and the dynamic hotkey hint are unit-testable. The app target renders each case
/// into an `NSMenuItem`.
public enum DictationMenuItem: Equatable, Sendable {
    /// The disabled live status line; the argument is the state word, rendered on
    /// its own (e.g. "Idle") so it reads without a redundant label.
    case status(String)
    /// The dynamic "Hold <key> to talk" hint, derived from the current trigger.
    case hotkeyHint(String)
    /// The disabled status line shown while a newer version downloads silently in
    /// the background; the argument is the version being fetched.
    case updateDownloading(version: String)
    /// The hybrid line shown once a downloaded update is validated — reads as a
    /// status line but becomes an actionable Restart under highlight; the argument
    /// is the ready version.
    case updateReady(version: String)
    case separator
    /// The Cleanup Model submenu; `selectedModelId` is the currently selected model
    /// id so the builder can check the right catalog row. `enabled` is false whenever
    /// cleanup is toggled off with a key present (`offByChoice`): the selector reads
    /// as unavailable — there IS a selection, it just cannot take effect — mirroring
    /// `translationLanguage`. In the no-key state the selector is not shown at all
    /// (replaced by `addOpenRouterKey`): with no key there is nothing to select.
    case cleanupModel(selectedModelId: String, enabled: Bool)
    /// The Translation Language submenu; `selected` is the currently selected
    /// target code so the renderer checks the right catalog row — mirrors
    /// `cleanupModel(selectedModelId:enabled:)`. `enabled` is false whenever cleanup
    /// is toggled off with a key present: a translate hold cannot run then, so the
    /// picker must read as unavailable rather than silently ignored. In the no-key
    /// state it is not shown at all (replaced by `addOpenRouterKey`).
    case translationLanguage(selected: String, enabled: Bool)
    /// The Clean Up Dictation switch; `isOn` drives its checkmark. Emitted only when a
    /// key is present (`on`/`offByChoice`), where the switch is always actionable — it
    /// is the way to turn cleanup on or off. In the no-key state the whole cleanup
    /// block is replaced by `addOpenRouterKey`, so an off-and-disabled toggle is
    /// unrepresentable by construction: without a key there is nothing to switch on.
    case cleanupToggle(isOn: Bool)
    /// Replaces the entire cleanup block in the no-key state: an action that opens
    /// Settings → Cleanup so the user can add an OpenRouter key. With no key there is
    /// nothing to configure, so the switch, translate, and model items are omitted
    /// and this single affordance takes their separator-delimited slot.
    case addOpenRouterKey
    case addVocabulary
    /// The mute-while-dictating switch; the argument is the current setting so the
    /// builder renders the checkmark. Closes the live-switch group.
    case muteWhileDictating(isOn: Bool)
    case settings
    case quit
    /// The About window entry; the first interactive item, in its own group
    /// directly below the status header.
    case about
}

/// Builds the ordered dropdown model from the current configuration.
public enum DictationMenu {
    /// The dropdown's top-level items in display order, grouped by role so each part
    /// reads where it is expected: the header (status, hotkey hint, and — while an
    /// update is downloading or ready — one update line directly below the hint and
    /// above the first separator), then the untitled cleanup block (see
    /// `cleanupBlock`), the vocabulary block (Add Vocabulary with the
    /// availability-independent mute switch adjacent to it), and the bottom section
    /// holding Settings, then About, then Quit — each group fenced by a separator. The
    /// hint reads "Hold <displayName> to talk" (e.g. "Hold Right ⌘ to talk").
    public static func items(
        trigger: HotkeyTrigger,
        selectedModelId: String,
        mutesSystemAudioWhileDictating: Bool,
        translationLanguage: String,
        cleanupAvailability: CleanupAvailability,
        update: UpdateIndication
    ) -> [DictationMenuItem] {
        let header: [DictationMenuItem] = [
            .status("Idle"),
            .hotkeyHint("Hold \(trigger.displayName) to talk"),
        ] + updateHeaderLine(for: update)
        let rest: [DictationMenuItem] = [
            .separator,
        ] + cleanupBlock(
            selectedModelId: selectedModelId,
            translationLanguage: translationLanguage,
            availability: cleanupAvailability
        ) + [
            .separator,
            .addVocabulary,
            .muteWhileDictating(isOn: mutesSystemAudioWhileDictating),
            .separator,
            .settings,
            .about,
            .quit,
        ]
        return header + rest
    }

    /// The untitled, separator-delimited cleanup block. With a key present it holds
    /// the three cleanup controls in top-down order — the on/off switch, the model
    /// selector, then the translate target (matching the Settings pane's Cleanup
    /// section); the switch stays active even in `offByChoice` (it is the way back
    /// on), while model and translate read as unavailable there (enabled only when
    /// cleanup is on). With no key there is nothing to configure, so the whole block
    /// collapses to the single add-key affordance — the switch, model, and translate
    /// items are omitted, not shown disabled.
    private static func cleanupBlock(
        selectedModelId: String,
        translationLanguage: String,
        availability: CleanupAvailability
    ) -> [DictationMenuItem] {
        switch availability {
        case .offNoKey:
            return [.addOpenRouterKey]
        case .on, .offByChoice:
            return [
                .cleanupToggle(isOn: availability.isOn),
                .cleanupModel(selectedModelId: selectedModelId, enabled: availability.isOn),
                .translationLanguage(selected: translationLanguage, enabled: availability.isOn),
            ]
        }
    }

    /// The single header line, if any, rendering the update state directly below the
    /// hotkey hint. `idle`/`checking` add nothing HERE: the always-visible update row
    /// is the app-target's persistent, in-place-mutated item (see AppDelegate+UpdateMenu),
    /// which owns the actionable "Check for Updates…"/"Checking…"/hybrid-Restart forms;
    /// this pure model only spells the disabled `downloading`/`ready` status text that
    /// the exact-sequence tests pin. (The two representations are documented-spec vs
    /// runtime; see the follow-ups ledger.)
    private static func updateHeaderLine(for update: UpdateIndication) -> [DictationMenuItem] {
        switch update {
        case .idle, .checking:
            return []
        case .downloading(let version):
            return [.updateDownloading(version: version)]
        case .ready(let version):
            return [.updateReady(version: version)]
        }
    }
}
