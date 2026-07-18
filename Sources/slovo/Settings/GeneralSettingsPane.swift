import SwiftUI
import SlovoCore

/// Settings → General: the push-to-talk key and the recognition language.
@MainActor
struct GeneralSettingsPane: View {
    // Unowned, not strong: AppDelegate (the only conformer) is an app-lifetime
    // singleton that always outlives this pane, matching DictationMenuBuilder's
    // `unowned let target: AppDelegate`.
    unowned let actions: any SettingsActions
    @State private var trigger: HotkeyTrigger
    @State private var language: Language
    @State private var launchAtLogin: Bool
    @State private var automaticallyInstallsUpdates: Bool

    init(actions: any SettingsActions) {
        self.actions = actions
        let config = actions.currentConfig()
        _trigger = State(initialValue: config.trigger)
        _language = State(initialValue: config.language)
        _automaticallyInstallsUpdates = State(initialValue: config.automaticallyInstallsUpdates)
        // Seeded from the live login-item state, not persisted config: the system
        // service is the source of truth, and the toggle defaults off until the
        // user opts in.
        _launchAtLogin = State(initialValue: actions.launchAtLoginEnabled())
    }

    var body: some View {
        Form {
            Section("Dictation") {
                Picker("Push-to-talk key", selection: $trigger) {
                    ForEach(HotkeyTrigger.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .onChange(of: trigger) { _, newValue in actions.setTrigger(newValue) }
                Picker("Recognition language", selection: $language) {
                    Text("Auto").tag(Language.auto)
                    ForEach(RecognitionLanguageCatalog.options) { option in
                        Text(option.displayName).tag(Language(rawValue: option.code))
                    }
                }
                .onChange(of: language) { _, newValue in actions.setRecognitionLanguage(newValue) }
                Text("Auto handles mixed Russian + English best.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in actions.setLaunchAtLogin(newValue) }
            }
            Section("Updates") {
                Toggle("Automatically install updates", isOn: $automaticallyInstallsUpdates)
                    .onChange(of: automaticallyInstallsUpdates) { _, newValue in
                        actions.setAutomaticallyInstallsUpdates(newValue)
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear {
            // Windows are cached and reopened, not recreated — without this, a
            // trigger/language change made elsewhere (e.g. the dropdown) would
            // show stale here until the app relaunches.
            let config = actions.currentConfig()
            trigger = config.trigger
            language = config.language
            // The login item can be toggled off outside the app (System Settings),
            // so re-read the live state rather than trust the cached value.
            launchAtLogin = actions.launchAtLoginEnabled()
            automaticallyInstallsUpdates = config.automaticallyInstallsUpdates
        }
    }
}
