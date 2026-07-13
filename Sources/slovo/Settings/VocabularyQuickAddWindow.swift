import AppKit
import SwiftUI

/// The compact "Add Vocabulary…" utility window opened from the dropdown — a text
/// field plus Add / Cancel — replacing the old modal alert. It reuses the same
/// comma-separated parsing as the Settings vocabulary pane (via `addVocabulary`).
@MainActor
final class VocabularyQuickAddWindow {
    private var windowController: NSWindowController?
    private let onAdd: (String) -> Void

    init(onAdd: @escaping (String) -> Void) {
        self.onAdd = onAdd
    }

    func show() {
        // A fresh view every call, even when the window chrome is reused —
        // otherwise text left in the field from a cancelled add would still be
        // there on reopen.
        let view = VocabularyQuickAddView(
            onAdd: { [weak self] terms in
                self?.onAdd(terms)
                self?.close()
            },
            onCancel: { [weak self] in self?.close() }
        )
        if let windowController {
            windowController.window?.contentViewController = NSHostingController(rootView: view)
        } else {
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Add Vocabulary"
            window.styleMask = [.titled, .closable]
            self.windowController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
    }

    private func close() {
        windowController?.close()
    }
}

/// The quick-add form. Kept separate from the window so the SwiftUI body stays
/// small and previewable.
@MainActor
private struct VocabularyQuickAddView: View {
    let onAdd: (String) -> Void
    let onCancel: () -> Void
    @State private var terms: String = ""
    @FocusState private var isTermsFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comma-separated terms that cleanup must preserve verbatim.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("GitHub, OAuth, PostgreSQL", text: $terms)
                .focused($isTermsFieldFocused)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Add") { onAdd(terms) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(terms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
        .defaultFocus($isTermsFieldFocused, true)
    }
}
