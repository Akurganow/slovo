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

    func setTrigger(_ trigger: HotkeyTrigger)
    func setRecognitionLanguage(_ language: Language)
    func setCleanupModel(_ modelId: String)
    func setWritingStyle(_ style: WritingStyle)
    func saveOpenRouterKey(_ key: String)

    func listVocabulary() -> [VocabularyRecord]
    func addVocabulary(_ commaSeparatedTerms: String)
    func removeVocabulary(id: Int64)
}
