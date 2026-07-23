import AppKit
import SwiftUI

/// The compact "Add OpenRouter Key…" window opened from the dropdown in the no-key
/// state — a secure field plus Save / Cancel, and nothing else. Save routes through
/// the app's existing key-save path (`SettingsActions.saveOpenRouterKey` → the
/// provider store and the availability funnel), so adding a key here repaints every
/// surface exactly as saving from the Settings pane does. A user-initiated window,
/// so activating it is not the focus-stealing the house rule forbids.
@MainActor
final class OpenRouterKeyWindow {
    private var windowController: NSWindowController?
    private let onSave: (String) -> Void

    init(onSave: @escaping (String) -> Void) {
        self.onSave = onSave
    }

    func show() {
        // A fresh view every call, even when the window chrome is reused — otherwise
        // a key left in the field from a cancelled entry would still be there on reopen.
        let view = OpenRouterKeyView(
            onSave: { [weak self] key in
                self?.onSave(key)
                self?.close()
            },
            onCancel: { [weak self] in self?.close() }
        )
        if let windowController {
            windowController.window?.contentViewController = NSHostingController(rootView: view)
        } else {
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Add OpenRouter Key"
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

/// The key-entry form. Kept separate from the window so the SwiftUI body stays small
/// and previewable.
@MainActor
private struct OpenRouterKeyView: View {
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State private var key: String = ""

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stored in your Keychain. Create one at openrouter.ai/keys.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            InitialFocusSecureField(placeholder: "Enter your OpenRouter API key", text: $key)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedKey.isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }

    private func save() {
        guard !trimmedKey.isEmpty else { return }
        onSave(trimmedKey)
    }
}

/// A secure text field that grabs first-responder when it joins the window, so the
/// user can type the key immediately. Mirrors the plain `InitialFocusTextField` used
/// by the vocabulary quick-add — the codebase's proven route for reliable initial
/// focus in an `NSHostingController` window (SwiftUI `@FocusState`-on-appear is
/// unreliable there).
@MainActor
private struct InitialFocusSecureField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = InitialFirstResponderSecureField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.isBezeled = true
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        return field
    }

    func updateNSView(_ field: NSSecureTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
        }
    }
}

@MainActor
private final class InitialFirstResponderSecureField: NSSecureTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.initialFirstResponder = self
        window.makeFirstResponder(self)
    }
}
