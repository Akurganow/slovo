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
    @State private var hasSavedKey: Bool
    @State private var useSpellCheckHints: Bool

    init(actions: any SettingsActions) {
        self.actions = actions
        let config = actions.currentConfig()
        _selectedModelId = State(initialValue: config.openRouterModel)
        _writingStyle = State(initialValue: config.writingStyle)
        _translationLanguage = State(initialValue: config.translationTargetLanguage.rawValue)
        _hasSavedKey = State(initialValue: actions.hasOpenRouterKey())
        _useSpellCheckHints = State(initialValue: config.useSpellCheckHints)
    }

    private var catalogIds: [String] { CleanupModelCatalog.options.map(\.id) }

    private var trimmedCustomModelId: String {
        customModelId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedApiKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            cleanupSection
            apiKeySection
            spellCheckHintsSection
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
            hasSavedKey = actions.hasOpenRouterKey()
            useSpellCheckHints = config.useSpellCheckHints
        }
    }

    // Model, writing style, and translate target share one section: they are the
    // knobs of a single cleanup step, so grouping them makes the relationship —
    // including the hidden Control-to-translate trigger — visible at a glance. Each
    // row is its own view so no single closure grows unwieldy.
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
                    Button("Save", action: saveKey)
                        .disabled(trimmedApiKey.isEmpty)
                }
                if hasSavedKey {
                    Label("A key is saved in your Keychain.", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Stored in your Keychain. Create one at openrouter.ai/keys.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
        hasSavedKey = true
    }
}
