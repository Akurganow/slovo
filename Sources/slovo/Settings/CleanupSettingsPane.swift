import SwiftUI
import SlovoCore

/// Settings → Cleanup: the cleanup model (catalog + custom id), writing style, and
/// the OpenRouter API key.
@MainActor
struct CleanupSettingsPane: View {
    // Unowned, not strong: AppDelegate (the only conformer) is an app-lifetime
    // singleton that always outlives this pane, matching DictationMenuBuilder's
    // `unowned let target: AppDelegate`.
    unowned let actions: any SettingsActions
    @State private var selectedModelId: String
    @State private var customModelId: String = ""
    @State private var writingStyle: WritingStyle
    @State private var apiKey: String = ""
    @State private var hasSavedKey: Bool
    @State private var useSpellCheckHints: Bool

    init(actions: any SettingsActions) {
        self.actions = actions
        let config = actions.currentConfig()
        _selectedModelId = State(initialValue: config.openRouterModel)
        _writingStyle = State(initialValue: config.writingStyle)
        _hasSavedKey = State(initialValue: actions.hasOpenRouterKey())
        _useSpellCheckHints = State(initialValue: config.useSpellCheckHints)
    }

    private var catalogIds: [String] { CleanupModelCatalog.options.map(\.id) }

    var body: some View {
        Form {
            modelSection
            writingStyleSection
            apiKeySection
            spellCheckHintsSection
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear {
            // Re-seed on every reappearance — the Settings window is cached, so a
            // cleanup-model change made from the dropdown must not read stale here.
            let config = actions.currentConfig()
            selectedModelId = config.openRouterModel
            writingStyle = config.writingStyle
            hasSavedKey = actions.hasOpenRouterKey()
            useSpellCheckHints = config.useSpellCheckHints
        }
    }

    private var spellCheckHintsSection: some View {
        // The input-language hint has no toggle; only the spell pass is user-gated.
        Section("Language hints") {
            Toggle("Use system spell-check hints", isOn: $useSpellCheckHints)
                .onChange(of: useSpellCheckHints) { _, enabled in actions.setSpellCheckHints(enabled) }
        }
    }

    private var modelSection: some View {
        Section("Cleanup model") {
            Picker("Model", selection: $selectedModelId) {
                ForEach(CleanupModelCatalog.options, id: \.id) { option in
                    Text(option.displayName).tag(option.id)
                }
                if !catalogIds.contains(selectedModelId) {
                    Text(selectedModelId).tag(selectedModelId)
                }
            }
            .onChange(of: selectedModelId) { _, newValue in actions.setCleanupModel(newValue) }

            HStack {
                TextField("Custom OpenRouter model id", text: $customModelId)
                Button("Use") {
                    let trimmed = customModelId.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    selectedModelId = trimmed
                    actions.setCleanupModel(trimmed)
                }
                .disabled(customModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var writingStyleSection: some View {
        Section("Writing style") {
            Picker("Style", selection: $writingStyle) {
                Text("Formal").tag(WritingStyle.formal)
                Text("Casual").tag(WritingStyle.casual)
                Text("Very casual").tag(WritingStyle.veryCasual)
            }
            .onChange(of: writingStyle) { _, newValue in actions.setWritingStyle(newValue) }
        }
    }

    private var apiKeySection: some View {
        Section("OpenRouter API key") {
            SecureField(hasSavedKey ? "A key is saved" : "Enter key", text: $apiKey)
            Button("Save key") {
                let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                actions.saveOpenRouterKey(trimmed)
                apiKey = ""
                hasSavedKey = true
            }
            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text("The key is stored in Keychain.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
