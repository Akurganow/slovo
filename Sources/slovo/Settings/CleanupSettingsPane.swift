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
    // Focus target for the no-key add-key affordance: with no key the model row
    // shows an "Add OpenRouter Key…" button in place of the picker, and it focuses
    // the key field below so the user lands where they type the key.
    @FocusState private var keyFieldFocused: Bool
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
        }
    }

    // The toggle displays the EFFECTIVE state (off-and-disabled with no key)
    // while writes go to the stored preference; a computed binding keeps the
    // display/preference split without onChange re-entry.
    private var masterSection: some View {
        Section {
            Toggle("Clean up dictation", isOn: Binding(
                get: { availability.isOn },
                set: { enabled in actions.setCleanupEnabled(enabled) }
            ))
            .disabled(!availability.isToggleEnabled)
            if let status = availability.settingsStatusLine {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // Model, writing style, and translate target share one section: they are the
    // knobs of a single cleanup step, so grouping them makes the relationship —
    // including the hidden Control-to-translate trigger — visible at a glance. Each
    // row is its own view so no single closure grows unwieldy.
    private var cleanupSection: some View {
        // The model row carries its own no-key/off logic (replace vs disable); the
        // other two are plain dependent controls, grayed whenever cleanup is off.
        Section("Cleanup") {
            modelRow
            writingStyleRow
                .disabled(!availability.isOn)
            translateRow
                .disabled(!availability.isOn)
        }
    }

    @ViewBuilder private var modelRow: some View {
        if availability == .offNoKey {
            // No key: nothing to select, so the picker is REPLACED by the affordance
            // that fixes that — focus the key field below so the user can add a key.
            addKeyButton
        } else {
            modelPicker
                .disabled(!availability.isOn)
        }
    }

    private var addKeyButton: some View {
        Button("Add OpenRouter Key…") { keyFieldFocused = true }
    }

    @ViewBuilder private var modelPicker: some View {
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

    @ViewBuilder private var translateRow: some View {
        // No Auto row: a translate target must be a concrete language (the fail-closed
        // config guard rejects the sentinel), unlike the recognition-language picker.
        Picker("Translate to", selection: $translationLanguage) {
            ForEach(RecognitionLanguageCatalog.options) { option in
                Text(option.displayName).tag(option.code)
            }
        }
        .onChange(of: translationLanguage) { _, newCode in
            actions.setTranslationLanguage(Language(rawValue: newCode))
        }
        Text("Used when you hold Control while dictating.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var apiKeySection: some View {
        Section("OpenRouter API key") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    SecureField("Enter a new key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .focused($keyFieldFocused)
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
            Toggle("Use system spell-check hints", isOn: $useSpellCheckHints)
                .onChange(of: useSpellCheckHints) { _, enabled in actions.setSpellCheckHints(enabled) }
            Text("Spell-check findings from your Mac guide cleanup toward the right words.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
