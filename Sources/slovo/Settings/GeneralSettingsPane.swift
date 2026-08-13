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
    @State private var translateTrigger: HotkeyTrigger
    @State private var translateKeyIsAdditional: Bool
    @State private var language: Language
    @State private var usesVocabularyBias: Bool
    @ObservedObject private var dictationSoundCuePreferenceModel: DictationSoundCuePreferenceModel
    @State private var launchAtLogin: Bool
    @State private var automaticallyInstallsUpdates: Bool

    init(actions: any SettingsActions) {
        self.actions = actions
        let config = actions.currentConfig()
        _trigger = State(initialValue: config.trigger)
        _translateTrigger = State(initialValue: config.translateTrigger)
        _translateKeyIsAdditional = State(initialValue: config.translateKeyIsAdditional)
        _language = State(initialValue: config.language)
        _usesVocabularyBias = State(initialValue: config.usesVocabularyBias)
        _dictationSoundCuePreferenceModel = ObservedObject(
            wrappedValue: actions.dictationSoundCuePreferenceModel
        )
        _automaticallyInstallsUpdates = State(initialValue: config.automaticallyInstallsUpdates)
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
            // key/language change made elsewhere (e.g. the dropdown) would show
            // stale here until the app relaunches.
            seedHotkeys()
            let config = actions.currentConfig()
            language = config.language
            usesVocabularyBias = config.usesVocabularyBias
            // The login item can be toggled off outside the app (System Settings),
            // so re-read the live state rather than trust the cached value.
            launchAtLogin = actions.launchAtLoginEnabled()
            automaticallyInstallsUpdates = config.automaticallyInstallsUpdates
        }
    }

    private var dictationSettings: some View {
        Section("Dictation") {
            Picker("Push-to-talk key", selection: $trigger) {
                ForEach(HotkeyTrigger.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                        // One key cannot hold both roles: the other role's key stays
                        // visible but unselectable, so the collision is unreachable
                        // rather than merely refused when saved.
                        .selectionDisabled(option == translateTrigger)
                }
            }
            .onChange(of: trigger) { _, newValue in
                actions.setTrigger(newValue)
                seedHotkeys()
            }
            translateKeyRow
            additionalKeyRow
            Picker(selection: $language) {
                Text("Auto").tag(Language.auto)
                ForEach(RecognitionLanguageCatalog.options) { option in
                    Text(option.displayName).tag(Language(rawValue: option.code))
                }
            } label: {
                Text("Recognition language")
                Text("Auto handles mixed-language speech best.")
            }
            .onChange(of: language) { _, newValue in actions.setRecognitionLanguage(newValue) }
            vocabularyBiasRow
            Toggle("Sound Cues", isOn: Binding(
                get: { dictationSoundCuePreferenceModel.isEnabled },
                set: { actions.setPlaysDictationSoundCues($0) }
            ))
        }
    }

    /// The experimental switch that also biases speech recognition toward the top
    /// vocabulary terms. Its caption warns about the experiment itself rather than
    /// explaining the mechanism — the Vocabulary pane is where the terms are
    /// described. The caption is the label's SECOND Text (the documented
    /// title-and-subtitle builder), as on `additionalKeyRow`.
    private var vocabularyBiasRow: some View {
        Toggle(isOn: $usesVocabularyBias) {
            Text("Vocabulary bias (experimental)")
            Text("Experimental features may misbehave — use with care.")
        }
        .onChange(of: usesVocabularyBias) { _, newValue in actions.setVocabularyBias(newValue) }
    }

    /// The translate key beside the hold it joins: while the key is additional the row
    /// reads `<main key> + [key]`, so the two-key gesture is legible without extra
    /// copy; standalone drops the prefix and the dropdown stands alone.
    private var translateKeyRow: some View {
        LabeledContent("Translate key") {
            HStack(spacing: 6) {
                if translateKeyIsAdditional {
                    Text("\(trigger.displayName) +")
                }
                Picker("Translate key", selection: $translateTrigger) {
                    ForEach(HotkeyTrigger.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                            .selectionDisabled(option == trigger)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
        .onChange(of: translateTrigger) { _, newValue in
            actions.setTranslateTrigger(newValue)
            seedHotkeys()
        }
    }

    /// The switch that decides how the translate key is used. Its hint names only the
    /// OFF state: the row above already shows the on state as `<key> + [key]`, so
    /// spelling that out again would cost a line and say nothing new.
    /// The hint is the label's SECOND Text, the documented
    /// title-and-subtitle builder: it renders as attached secondary text inside the
    /// same row, where a sibling Text would become a row of its own behind a divider.
    private var additionalKeyRow: some View {
        Toggle(isOn: $translateKeyIsAdditional) {
            Text("Use as additional key")
            Text("Off, hold it on its own to dictate with translation.")
        }
        .onChange(of: translateKeyIsAdditional) { _, newValue in
            actions.setTranslateKeyIsAdditional(newValue)
            seedHotkeys()
        }
    }

    /// Snaps the key controls back to what the app actually persisted. The store fails
    /// a colliding pair closed, so a refused change must not linger on screen — and
    /// errors here never open a dialog (Slovo must not steal focus).
    private func seedHotkeys() {
        let config = actions.currentConfig()
        trigger = config.trigger
        translateTrigger = config.translateTrigger
        translateKeyIsAdditional = config.translateKeyIsAdditional
    }
}
