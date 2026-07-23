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
    /// The Cleanup Model submenu; the argument is the currently selected model id so
    /// the builder can check the right catalog row.
    case cleanupModel(selectedModelId: String)
    /// The Translation Language submenu; `selected` is the currently selected
    /// target code so the renderer checks the right catalog row — mirrors
    /// `cleanupModel(selectedModelId:)`. `enabled` is false whenever cleanup is
    /// effectively off: a translate hold cannot run then, so the picker must read
    /// as unavailable rather than silently ignored.
    case translationLanguage(selected: String, enabled: Bool)
    /// The Clean Up Dictation switch; carries the full availability so the
    /// renderer can show off-and-disabled for the no-key state.
    case cleanupToggle(availability: CleanupAvailability)
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
    /// above the first separator), About as the first interactive item in its own
    /// group (echoing the app-menu convention), the live switches (cleanup model,
    /// translate target, mute), the window openers (Add Vocabulary, Settings), and
    /// Quit isolated last — each group fenced by a separator. The hint reads
    /// "Hold <displayName> to talk" (e.g. "Hold Right ⌘ to talk").
    ///
    /// Grouping exception (deliberate): in the `ready` state the update line is an
    /// ACTIONABLE hybrid row that lives inside the otherwise-disabled status header
    /// with no separator of its own, so About is the first interactive item in
    /// every state except `ready`. `hidden` adds no line — the dropdown is exactly
    /// today's.
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
            .about,
            .separator,
            .cleanupModel(selectedModelId: selectedModelId),
            .translationLanguage(selected: translationLanguage, enabled: cleanupAvailability.isOn),
            .cleanupToggle(availability: cleanupAvailability),
            .muteWhileDictating(isOn: mutesSystemAudioWhileDictating),
            .separator,
            .addVocabulary,
            .settings,
            .separator,
            .quit,
        ]
        return header + rest
    }

    /// The single header line, if any, rendering the update state directly below
    /// the hotkey hint: `hidden` adds nothing, while `downloading` and `ready` each
    /// map to their one pinned item. The map is intentionally near-identity — the
    /// lifecycle's real state is `UpdateIndication`, whose `hidden` has no rendered
    /// form and so stays out of `DictationMenuItem`.
    private static func updateHeaderLine(for update: UpdateIndication) -> [DictationMenuItem] {
        switch update {
        case .hidden:
            return []
        case .downloading(let version):
            return [.updateDownloading(version: version)]
        case .ready(let version):
            return [.updateReady(version: version)]
        }
    }
}
