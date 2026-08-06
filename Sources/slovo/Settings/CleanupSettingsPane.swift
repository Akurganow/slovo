import SwiftUI
import SlovoCore

/// Settings → Cleanup: the cleanup step (model, writing style, translate target),
/// the OpenRouter API key, and the spell-check language hints.
@MainActor
struct CleanupSettingsPane: View {
    // Unowned, not strong: AppDelegate (the only conformer) is an app-lifetime
    // singleton that always outlives this pane, matching DictationMenuBuilder's
    // `unowned let target: AppDelegate`.
    unowned let actions: any SettingsActions
    @State private var selectedModelId: String
    @State private var customModelId: String = ""
    @State private var writingStyle: WritingStyle
    @State private var translationLanguage: String
    @State private var apiKey: String = ""
    @State private var isConfirmingKeyRemoval = false
    @State private var useSpellCheckHints: Bool
    // The keys are edited in the General pane, so this cached window re-reads them
    // on appear; the target picker's own caption names them.
    @State private var hotkeys: HotkeyConfiguration
    // The observed model, not a value snapshot (spec D1): the subscription
    // repaints the pane on any funnel write in the same runloop — no re-fetch
    // sites, nothing to go stale.
    @ObservedObject private var availabilityModel: CleanupAvailabilityModel

    init(actions: any SettingsActions) {
        self.actions = actions
        let config = actions.currentConfig()
        _selectedModelId = State(initialValue: config.openRouterModel)
        _writingStyle = State(initialValue: config.writingStyle)
        _translationLanguage = State(initialValue: config.translationTargetLanguage.rawValue)
        _useSpellCheckHints = State(initialValue: config.useSpellCheckHints)
        _hotkeys = State(initialValue: config.hotkeyConfiguration)
        _availabilityModel = ObservedObject(wrappedValue: actions.cleanupAvailabilityModel)
    }

    private var availability: CleanupAvailability { availabilityModel.availability }

    // offNoKey is definitionally "no key" (derive()'s keyPresent = false axis),
    // so the observed availability is the single truthful key-presence signal —
    // no manual snapshot to drift after a failed save or remove.
    private var hasKey: Bool { availability != .offNoKey }

    private var catalogIds: [String] { CleanupModelCatalog.options.map(\.id) }

    private var trimmedCustomModelId: String {
        customModelId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedApiKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            masterSection
            cleanupSection
                .disabled(!availability.isOn)
            apiKeySection
            spellCheckHintsSection
                .disabled(!availability.isOn)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear {
            // Re-seed on every reappearance — the Settings window is cached, so a
            // change made from the dropdown must not read stale here.
            let config = actions.currentConfig()
            selectedModelId = config.openRouterModel
            writingStyle = config.writingStyle
            translationLanguage = config.translationTargetLanguage.rawValue
            useSpellCheckHints = config.useSpellCheckHints
            hotkeys = config.hotkeyConfiguration
        }
    }

    // The toggle displays the EFFECTIVE state (off-and-disabled with no key)
    // while writes go to the stored preference; a computed binding keeps the
    // display/preference split without onChange re-entry. The status line rides the
    // label's SECOND Text (the documented title-and-subtitle builder) so it stays
    // attached to the toggle it explains — a sibling Text would sit behind a divider.
    private var masterSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { availability.isOn },
                set: { enabled in actions.setCleanupEnabled(enabled) }
            )) {
                Text("Clean up dictation")
                if let status = availability.settingsStatusLine {
                    Text(status)
                }
            }
            .disabled(!availability.isToggleEnabled)
        }
    }

    // Model, writing style, and translate target share one section: they are the
    // knobs of a single cleanup step, so grouping them shows at a glance that
    // translation rides on cleanup — the target's own caption names the key that asks
    // for it. Each row is its own view so no single closure grows unwieldy.
    private var cleanupSection: some View {
        Section("Cleanup") {
            modelRow
            writingStyleRow
            translateRow
        }
    }

    @ViewBuilder private var modelRow: some View {
        Picker("Model", selection: $selectedModelId) {
            ForEach(CleanupModelCatalog.options, id: \.id) { option in
                Text(option.displayName).tag(option.id)
            }
            if !catalogIds.contains(selectedModelId) {
                Text(selectedModelId).tag(selectedModelId)
            }
        }
        .onChange(of: selectedModelId) { _, newValue in actions.setCleanupModel(newValue) }

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("openrouter/model-id", text: $customModelId)
                    .textFieldStyle(.roundedBorder)
                Button("Use", action: useCustomModel)
                    .disabled(trimmedCustomModelId.isEmpty)
            }
            Text("Any model id from openrouter.ai/models. Needs your key below.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var writingStyleRow: some View {
        Picker("Writing style", selection: $writingStyle) {
            Text("Formal").tag(WritingStyle.formal)
            Text("Casual").tag(WritingStyle.casual)
            Text("Very casual").tag(WritingStyle.veryCasual)
        }
        .onChange(of: writingStyle) { _, newValue in actions.setWritingStyle(newValue) }
    }

    private var translateRow: some View {
        // No Auto row: a translate target must be a concrete language (the fail-closed
        // config guard rejects the sentinel), unlike the recognition-language picker.
        Picker(selection: $translationLanguage) {
            ForEach(RecognitionLanguageCatalog.options) { option in
                Text(option.displayName).tag(option.code)
            }
        } label: {
            Text("Translate to")
            Text(translateCaption)
        }
        .onChange(of: translationLanguage) { _, newCode in
            actions.setTranslationLanguage(Language(rawValue: newCode))
        }
    }

    /// Names the gesture the user actually has: the translate key is configurable,
    /// and standing alone its hold IS the dictation rather than something added to
    /// one. Same fork as the menu hint and the About guide, phrased for this row.
    private var translateCaption: String {
        let key = hotkeys.translate.displayName
        switch hotkeys.translateGesture {
        case .additional: return "Used when you add \(key) while dictating."
        case .standalone: return "Used when you dictate with \(key) held."
        }
    }

    private var apiKeySection: some View {
        Section("OpenRouter API key") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    SecureField("Enter a new key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    Button("Save", action: saveKey)
                        .disabled(trimmedApiKey.isEmpty)
                }
                if hasKey {
                    savedKeyRow
                } else {
                    Text("Stored in your Keychain. Create one at openrouter.ai/keys.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // Removal is destructive and confirmed in place: it flips cleanup to
    // offNoKey, so a slip must not be one click — and the dialog stays inside
    // the Settings window (house rule: never a separate alert window).
    private var savedKeyRow: some View {
        HStack {
            Label("A key is saved in your Keychain.", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Remove Key…", role: .destructive) { isConfirmingKeyRemoval = true }
        }
        .confirmationDialog(
            "Remove the OpenRouter API key?",
            isPresented: $isConfirmingKeyRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove Key", role: .destructive, action: removeSavedKey)
        } message: {
            Text("Cleanup will turn off until you add a key again.")
        }
    }

    private var spellCheckHintsSection: some View {
        // The input-language hint has no toggle; only the spell pass is user-gated.
        Section("Language hints") {
            Toggle(isOn: $useSpellCheckHints) {
                Text("Use system spell-check hints")
                Text("Your Mac's spell-check guides cleanup to the right words.")
            }
            .onChange(of: useSpellCheckHints) { _, enabled in actions.setSpellCheckHints(enabled) }
        }
    }

    private func useCustomModel() {
        guard !trimmedCustomModelId.isEmpty else { return }
        selectedModelId = trimmedCustomModelId
        actions.setCleanupModel(trimmedCustomModelId)
        customModelId = ""
    }

    private func saveKey() {
        guard !trimmedApiKey.isEmpty else { return }
        actions.saveOpenRouterKey(trimmedApiKey)
        apiKey = ""
    }

    private func removeSavedKey() {
        actions.removeOpenRouterKey()
    }
}
