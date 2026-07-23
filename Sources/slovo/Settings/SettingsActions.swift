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
    /// The effective cleanup state and its cause, for the pane's master toggle,
    /// status line, and disabled sections.
    func cleanupAvailability() -> CleanupAvailability
    /// Whether Slovo is registered to open at login (reads the system login-item
    /// service; like `hasOpenRouterKey()`, an attributes-only system read).
    func launchAtLoginEnabled() -> Bool

    func setTrigger(_ trigger: HotkeyTrigger)
    func setRecognitionLanguage(_ language: Language)
    func setTranslationLanguage(_ language: Language)
    func setCleanupModel(_ modelId: String)
    func setWritingStyle(_ style: WritingStyle)
    func setSpellCheckHints(_ enabled: Bool)
    func setCleanupEnabled(_ enabled: Bool)
    func setAutomaticallyInstallsUpdates(_ enabled: Bool)
    func setLaunchAtLogin(_ enabled: Bool)
    func saveOpenRouterKey(_ key: String)

    func listVocabulary() -> [VocabularyRecord]
    func addVocabulary(_ commaSeparatedTerms: String)
    func removeVocabulary(id: Int64)
}
