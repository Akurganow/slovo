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

    init(actions: any SettingsActions) {
        self.actions = actions
        let config = actions.currentConfig()
        _trigger = State(initialValue: config.trigger)
        _language = State(initialValue: config.language)
    }

    var body: some View {
        Form {
            Section("Push-to-talk key") {
                Picker("Hold to talk", selection: $trigger) {
                    ForEach(HotkeyTrigger.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .onChange(of: trigger) { _, newValue in actions.setTrigger(newValue) }
            }
            Section("Recognition language") {
                Picker("Language", selection: $language) {
                    Text("Automatic").tag(Language.auto)
                    Text("Russian").tag(Language.ru)
                    Text("English").tag(Language.en)
                }
                .onChange(of: language) { _, newValue in actions.setRecognitionLanguage(newValue) }
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
        }
    }
}
