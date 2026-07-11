import SwiftUI
import SlovoCore

/// Settings → Vocabulary: the table of stored terms with add and remove.
@MainActor
struct VocabularySettingsPane: View {
    // Unowned, not strong: AppDelegate (the only conformer) is an app-lifetime
    // singleton that always outlives this pane, matching DictationMenuBuilder's
    // `unowned let target: AppDelegate`.
    unowned let actions: any SettingsActions
    @State private var records: [VocabularyRecord]
    @State private var newTerms: String = ""

    init(actions: any SettingsActions) {
        self.actions = actions
        _records = State(initialValue: actions.listVocabulary())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                ForEach(records, id: \.id) { record in
                    Text(record.term)
                }
                .onDelete(perform: delete)
            }
            HStack {
                TextField("GitHub, OAuth, PostgreSQL", text: $newTerms)
                Button("Add") {
                    let input = newTerms
                    guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    actions.addVocabulary(input)
                    newTerms = ""
                    records = actions.listVocabulary()
                }
                .disabled(newTerms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 420, height: 360)
        .onAppear {
            // Same reason as the other panes: the window is cached, not recreated.
            records = actions.listVocabulary()
        }
    }

    private func delete(at offsets: IndexSet) {
        for id in offsets.compactMap({ records[$0].id }) {
            actions.removeVocabulary(id: id)
        }
        records = actions.listVocabulary()
    }
}
