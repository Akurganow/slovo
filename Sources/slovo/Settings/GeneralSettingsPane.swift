import SwiftUI
import SlovoCore

/// Settings → General: the push-to-talk key and the recognition language.
@MainActor
struct GeneralSettingsPane: View {
    // Unowned, not strong: AppDelegate (the only conformer) is an app-lifetime
    // singleton that always outlives this pane, matching DictationMenuBuilder's
    // `unowned let target: AppDelegate`.
    unowned let actions: any SettingsActions
    @ObservedObject private var store: AppStore
    @State private var launchAtLogin: Bool

    init(actions: any SettingsActions) {
        self.actions = actions
        _store = ObservedObject(wrappedValue: actions.store)
        // Seeded from the live login-item state, not persisted config: the system
        // service is the source of truth, and the toggle defaults off until the
        // user opts in.
        _launchAtLogin = State(initialValue: actions.launchAtLoginEnabled())
    }

    var body: some View {
        Form {
            dictationSettings
            Section("Startup") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in actions.setLaunchAtLogin(newValue) }
            }
            Section("Updates") {
                Toggle("Automatically install updates", isOn: store.binding(\.automaticallyInstallsUpdates))
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear {
            // The login item can be toggled off outside the app (System Settings),
            // so re-read the live state rather than trust the cached value.
            launchAtLogin = actions.launchAtLoginEnabled()
        }
    }

    private var dictationSettings: some View {
        Section("Dictation") {
            Picker("Push-to-talk key", selection: store.binding(\.trigger)) {
                ForEach(HotkeyTrigger.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                        // One key cannot hold both roles: the other role's key stays
                        // visible but unselectable, so the collision is unreachable
                        // rather than merely refused when saved.
                        .selectionDisabled(option == store.state.config.translateTrigger)
                }
            }
            translateKeyRow
            additionalKeyRow
            Picker(selection: store.binding(\.language)) {
                Text("Auto").tag(Language.auto)
                ForEach(RecognitionLanguageCatalog.options) { option in
                    Text(option.displayName).tag(Language(rawValue: option.code))
                }
            } label: {
                Text("Recognition language")
                Text("Auto handles mixed-language speech best.")
            }
            vocabularyBiasRow
            Toggle("Sound Cues", isOn: store.binding(\.playsDictationSoundCues))
        }
    }

    /// The experimental switch that also biases speech recognition toward the top
    /// vocabulary terms. Its caption warns about the experiment itself rather than
    /// explaining the mechanism — the Vocabulary pane is where the terms are
    /// described. The caption is the label's SECOND Text (the documented
    /// title-and-subtitle builder), as on `additionalKeyRow`.
    private var vocabularyBiasRow: some View {
        Toggle(isOn: store.binding(\.usesVocabularyBias)) {
            Text("Vocabulary bias (experimental)")
            Text("Experimental features may misbehave — use with care.")
        }
    }

    /// The translate key beside the hold it joins: while the key is additional the row
    /// reads `<main key> + [key]`, so the two-key gesture is legible without extra
    /// copy; standalone drops the prefix and the dropdown stands alone.
    private var translateKeyRow: some View {
        LabeledContent("Translate key") {
            HStack(spacing: 6) {
                if store.state.config.translateKeyIsAdditional {
                    Text("\(store.state.config.trigger.displayName) +")
                }
                Picker("Translate key", selection: store.binding(\.translateTrigger)) {
                    ForEach(HotkeyTrigger.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                            .selectionDisabled(option == store.state.config.trigger)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    /// The switch that decides how the translate key is used. Its hint names only the
    /// OFF state: the row above already shows the on state as `<key> + [key]`, so
    /// spelling that out again would cost a line and say nothing new.
    /// The hint is the label's SECOND Text, the documented
    /// title-and-subtitle builder: it renders as attached secondary text inside the
    /// same row, where a sibling Text would become a row of its own behind a divider.
    private var additionalKeyRow: some View {
        Toggle(isOn: store.binding(\.translateKeyIsAdditional)) {
            Text("Use as additional key")
            Text("Off, hold it on its own to dictate with translation.")
        }
    }
}
