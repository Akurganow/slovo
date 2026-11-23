import AppKit
import SwiftUI

/// The compact one-field entry window behind the dropdown's "Add OpenRouter Key…" and
/// "Add Vocabulary…" items: a caption, a field, Cancel and a confirm button. Confirm
/// passes the trimmed text to `onConfirm` and closes; Cancel and Esc close without
/// confirming. For the key, `onConfirm` is the app's key-save path, so adding a key
/// here repaints every surface exactly as saving from the Settings pane does. A
/// user-initiated window, so activating it is not the focus-stealing the house rule
/// forbids.
@MainActor
final class TextEntryWindow {
    /// Everything that differs between the two dialogs.
    struct Content {
        let windowTitle: String
        let caption: String
        let placeholder: String
        let confirmTitle: String
        let isSecure: Bool

        static let openRouterKey = Content(
            windowTitle: "Add OpenRouter Key",
            caption: "Stored in your Keychain. Create one at openrouter.ai/keys.",
            placeholder: "Enter your OpenRouter API key",
            confirmTitle: "Save",
            isSecure: true
        )

        static let vocabulary = Content(
            windowTitle: "Add Vocabulary",
            caption: "Comma-separated terms that cleanup must preserve verbatim.",
            placeholder: "GitHub, OAuth, PostgreSQL",
            confirmTitle: "Add",
            isSecure: false
        )
    }

    private let content: Content
    private let onConfirm: (String) -> Void
    private var windowController: NSWindowController?

    init(content: Content, onConfirm: @escaping (String) -> Void) {
        self.content = content
        self.onConfirm = onConfirm
    }

    func show() {
        // A fresh view every call, even when the window chrome is reused — otherwise
        // text left in the field from a cancelled entry would still be there on reopen.
        let view = TextEntryView(
            content: content,
            onConfirm: { [weak self] text in
                self?.onConfirm(text)
                self?.close()
            },
            onCancel: { [weak self] in self?.close() }
        )
        if let windowController {
            windowController.window?.contentViewController = NSHostingController(rootView: view)
        } else {
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = content.windowTitle
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

/// The entry form. Kept separate from the window so the SwiftUI body stays small
/// and previewable.
@MainActor
private struct TextEntryView: View {
    let content: TextEntryWindow.Content
    let onConfirm: (String) -> Void
    let onCancel: () -> Void
    @State private var text: String = ""

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(content.caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
            InitialFocusField(placeholder: content.placeholder, isSecure: content.isSecure, text: $text)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(content.confirmTitle, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedText.isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }

    private func confirm() {
        guard !trimmedText.isEmpty else { return }
        onConfirm(trimmedText)
    }
}

/// A text field that grabs first-responder when it joins the window, so the user can
/// type immediately — the codebase's proven route for reliable initial focus in an
/// `NSHostingController` window (SwiftUI `@FocusState`-on-appear is unreliable there).
/// A secure field is an `NSSecureTextField`, which cannot share a subclass with the
/// plain `NSTextField`, so each has a one-line subclass over `claimFirstResponder`.
@MainActor
private struct InitialFocusField: NSViewRepresentable {
    let placeholder: String
    let isSecure: Bool
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField = isSecure ? InitialFirstResponderSecureField() : InitialFirstResponderTextField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.isBezeled = true
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
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

private extension NSTextField {
    func claimFirstResponder() {
        guard let window else { return }
        window.initialFirstResponder = self
        window.makeFirstResponder(self)
    }
}

@MainActor
private final class InitialFirstResponderTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        claimFirstResponder()
    }
}

@MainActor
private final class InitialFirstResponderSecureField: NSSecureTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        claimFirstResponder()
    }
}
