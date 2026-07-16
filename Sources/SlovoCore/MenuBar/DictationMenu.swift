/// One top-level entry in the status-menu dropdown, AppKit-free so the item order
/// and the dynamic hotkey hint are unit-testable. The app target renders each case
/// into an `NSMenuItem`.
public enum DictationMenuItem: Equatable, Sendable {
    /// The disabled app-name header.
    case title(String)
    /// The disabled live status line; the argument is the initial state word,
    /// rendered as "Status: <word>".
    case status(String)
    /// The dynamic "Hold <key> to talk" hint, derived from the current trigger.
    case hotkeyHint(String)
    case separator
    /// The Cleanup Model submenu; the argument is the currently selected model id so
    /// the builder can check the right catalog row.
    case cleanupModel(selectedModelId: String)
    case addVocabulary
    /// The mute-while-dictating switch; the argument is the current setting so the
    /// builder renders the checkmark.
    case muteWhileDictating(isOn: Bool)
    case settings
    case quit
}

/// Builds the ordered dropdown model from the current configuration.
public enum DictationMenu {
    /// The dropdown's top-level items in display order. The hint reads
    /// "Hold <displayName> to talk" (e.g. "Hold Right ⌘ to talk"). The
    /// mute-while-dictating switch carries the live setting and sits after Add
    /// Vocabulary, before the trailing separator.
    public static func items(
        trigger: HotkeyTrigger,
        selectedModelId: String,
        mutesSystemAudioWhileDictating: Bool
    ) -> [DictationMenuItem] {
        [
            .title("Slovo"),
            .status("Idle"),
            .hotkeyHint("Hold \(trigger.displayName) to talk"),
            .separator,
            .cleanupModel(selectedModelId: selectedModelId),
            .addVocabulary,
            .muteWhileDictating(isOn: mutesSystemAudioWhileDictating),
            .separator,
            .settings,
            .quit,
        ]
    }
}
