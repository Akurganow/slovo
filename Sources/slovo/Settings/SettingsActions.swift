import SlovoCore

/// The panes' seam to the app: the store, which a pane observes and writes through
/// `update`, plus the actions whose effects live outside it. `AppDelegate`
/// implements it; the SwiftUI panes depend only on this seam, never on AppKit or
/// `AppDelegate`.
@MainActor
protocol SettingsActions: AnyObject {
    var store: AppStore { get }
    /// Whether Slovo is registered to open at login (reads the system login-item
    /// service).
    func launchAtLoginEnabled() -> Bool
    func setLaunchAtLogin(_ enabled: Bool)
    func saveOpenRouterKey(_ key: String)
    /// Deletes the saved OpenRouter key; key presence is read back into the store,
    /// so every surface flips to offNoKey live.
    func removeOpenRouterKey()
    func addVocabulary(_ commaSeparatedTerms: String)
    func removeVocabulary(id: Int64)
    /// Opens the bundled third-party notices file in the user's default handler.
    func openAcknowledgements()
}
