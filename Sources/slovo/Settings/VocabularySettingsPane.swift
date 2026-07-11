import SwiftUI
import SlovoCore

/// Settings → Vocabulary: an editable table of stored terms with the native
/// macOS ＋ / － control at the list's bottom-left (as in System Settings).
@MainActor
struct VocabularySettingsPane: View {
    // Unowned, not strong: AppDelegate (the only conformer) is an app-lifetime
    // singleton that always outlives this pane, matching DictationMenuBuilder's
    // `unowned let target: AppDelegate`.
    unowned let actions: any SettingsActions
    @State private var records: [VocabularyRecord]
    // Row ids mirror `VocabularyRecord.id` (`Int64?`), so the selection is optional-
    // typed to match the `List`/`ForEach` identity; nil ids never occur for stored
    // rows and are dropped on removal.
    @State private var selection = Set<Int64?>()
    @State private var newTerms: String = ""
    @State private var isAddingTerm = false

    init(actions: any SettingsActions) {
        self.actions = actions
        _records = State(initialValue: actions.listVocabulary())
    }

    private var trimmedNewTerms: String {
        newTerms.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(records, id: \.id) { record in
                    Text(record.term)
                }
                .onDelete(perform: delete)
            }
            .listStyle(.plain)
            Divider()
            editBar
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            // A single faint frame around list + toolbar, so the two read as one
            // editable table rather than a bare list with a detached button row.
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .padding()
        .frame(width: 420, height: 360)
        .onAppear {
            // Same reason as the other panes: the window is cached, not recreated.
            records = actions.listVocabulary()
        }
    }

    // The bottom-left ＋ / － bar of a macOS editable table. Icon-only borderless
    // buttons carry their meaning through accessibility labels, not visible text.
    private var editBar: some View {
        HStack(spacing: 0) {
            Button(action: presentAddTerm) {
                // A fixed frame + rectangular content shape make the whole cell
                // clickable, not just the glyph's pixels — otherwise the hit target
                // collapses to the icon and clicks feel like they keep missing.
                Image(systemName: "plus")
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Add term")
            }
            .popover(isPresented: $isAddingTerm, arrowEdge: .bottom) {
                addTermPopover
            }

            Button(action: removeSelected) {
                Image(systemName: "minus")
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Remove selected")
            }
            .disabled(selection.isEmpty)

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var addTermPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Comma-separated bulk add is preserved: the seam splits the input.
            TextField("GitHub, OAuth, PostgreSQL", text: $newTerms)
                .frame(width: 240)
            HStack {
                Spacer()
                Button("Add", action: addTerms)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedNewTerms.isEmpty)
            }
        }
        .padding()
    }

    private func presentAddTerm() {
        isAddingTerm = true
    }

    private func addTerms() {
        guard !trimmedNewTerms.isEmpty else { return }
        actions.addVocabulary(newTerms)
        newTerms = ""
        isAddingTerm = false
        records = actions.listVocabulary()
    }

    private func delete(at offsets: IndexSet) {
        for id in offsets.compactMap({ records[$0].id }) {
            actions.removeVocabulary(id: id)
        }
        records = actions.listVocabulary()
    }

    private func removeSelected() {
        for case let id? in selection {
            actions.removeVocabulary(id: id)
        }
        selection.removeAll()
        records = actions.listVocabulary()
    }
}
