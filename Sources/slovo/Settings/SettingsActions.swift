import SlovoCore

/// The actions a Settings pane can invoke. `AppDelegate` implements it and routes
/// each change to the correct live-apply path; the SwiftUI panes depend only on
/// this seam, never on AppKit or `AppDelegate`, so they stay previewable and the
/// wiring is checkable in isolation.
@MainActor
protocol SettingsActions: AnyObject {
    /// The persisted configuration a pane seeds its controls from.
    func currentConfig() -> Config
    /// Whether an OpenRouter key is present (attributes-only; never decrypts it).
    func hasOpenRouterKey() -> Bool
    /// The observable effective-cleanup state (and its cause) behind the pane's
    /// master toggle, status line, and disabled sections. The pane renders it
    /// live — the app's push funnel is its only writer (spec D1), and no
    /// snapshot/poll accessor exists so a pane cannot hold a stale copy.
    var cleanupAvailabilityModel: CleanupAvailabilityModel { get }
    /// The live Sound Cues preference shared by General Settings and the menu.
    var dictationSoundCuePreferenceModel: DictationSoundCuePreferenceModel { get }
    /// Whether Slovo is registered to open at login (reads the system login-item
    /// service; like `hasOpenRouterKey()`, an attributes-only system read).
    func launchAtLoginEnabled() -> Bool

    func setTrigger(_ trigger: HotkeyTrigger)
    func setTranslateTrigger(_ trigger: HotkeyTrigger)
    /// Whether the translate key rides on top of a push-to-talk hold rather than
    /// opening a dictation of its own.
    func setTranslateKeyIsAdditional(_ isAdditional: Bool)
    func setRecognitionLanguage(_ language: Language)
    func setTranslationLanguage(_ language: Language)
    func setCleanupModel(_ modelId: String)
    func setWritingStyle(_ style: WritingStyle)
    func setSpellCheckHints(_ enabled: Bool)
    /// The experimental switch that also hands the top vocabulary terms to the
    /// speech recognizer as a bias prompt.
    func setVocabularyBias(_ enabled: Bool)
    func setCleanupEnabled(_ enabled: Bool)
    func setPlaysDictationSoundCues(_ enabled: Bool)
    func setAutomaticallyInstallsUpdates(_ enabled: Bool)
    func setLaunchAtLogin(_ enabled: Bool)
    func saveOpenRouterKey(_ key: String)
    /// Deletes the saved OpenRouter key; availability refreshes through the
    /// app's push funnel, so every surface flips to offNoKey live.
    func removeOpenRouterKey()

    func listVocabulary() -> [VocabularyRecord]
    func addVocabulary(_ commaSeparatedTerms: String)
    func removeVocabulary(id: Int64)
}
