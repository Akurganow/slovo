/// One top-level entry in the status-menu dropdown, AppKit-free so the item order
/// and the dynamic hotkey hint are unit-testable. The app target renders each case
/// into an `NSMenuItem`.
public enum DictationMenuItem: Equatable, Sendable {
    /// The disabled app-name header.
    case title(String)
    /// The disabled live status line; the argument is the state word, rendered on
    /// its own (e.g. "Idle") so it reads without a redundant label.
    case status(String)
    /// The dynamic "Hold <key> to talk" hint, derived from the current trigger.
    case hotkeyHint(String)
    case separator
    /// The Cleanup Model submenu; the argument is the currently selected model id so
    /// the builder can check the right catalog row.
    case cleanupModel(selectedModelId: String)
    /// The Translation Language submenu; the argument is the currently selected
    /// target code so the renderer checks the right catalog row — mirrors
    /// `cleanupModel(selectedModelId:)`.
    case translationLanguage(selected: String)
    case addVocabulary
    /// The mute-while-dictating switch; the argument is the current setting so the
    /// builder renders the checkmark. Closes the live-switch group.
    case muteWhileDictating(isOn: Bool)
    /// The About window entry; sits in the window-opener group, between Add
    /// Vocabulary and Settings.
    case about
    case settings
    case quit
}

/// Builds the ordered dropdown model from the current configuration.
public enum DictationMenu {
    /// The dropdown's top-level items in display order, grouped by role so each part
    /// reads where it is expected: the header (title, status, hotkey hint), the live
    /// switches (cleanup model, translate target, mute), the window openers (Add
    /// Vocabulary, About, Settings), and the isolated Quit — each group fenced by a
    /// separator. The hint reads "Hold <displayName> to talk" (e.g. "Hold Right ⌘ to
    /// talk").
    public static func items(
        trigger: HotkeyTrigger,
        selectedModelId: String,
        mutesSystemAudioWhileDictating: Bool,
        translationLanguage: String
    ) -> [DictationMenuItem] {
        [
            .title("Slovo"),
            .status("Idle"),
            .hotkeyHint("Hold \(trigger.displayName) to talk"),
            .separator,
            .cleanupModel(selectedModelId: selectedModelId),
            .translationLanguage(selected: translationLanguage),
            .muteWhileDictating(isOn: mutesSystemAudioWhileDictating),
            .separator,
            .addVocabulary,
            .about,
            .settings,
            .separator,
            .quit,
        ]
    }
}
