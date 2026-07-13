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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comma-separated terms that cleanup must preserve verbatim.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            InitialFocusTextField(placeholder: "GitHub, OAuth, PostgreSQL", text: $terms)
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
    }
}

@MainActor
private struct InitialFocusTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = InitialFirstResponderTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.isBezeled = true
        textField.isEditable = true
        textField.isSelectable = true
        textField.usesSingleLineMode = true
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        if textField.stringValue != text {
            textField.stringValue = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text = textField.stringValue
        }
    }
}

@MainActor
private final class InitialFirstResponderTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.initialFirstResponder = self
        window.makeFirstResponder(self)
    }
}
