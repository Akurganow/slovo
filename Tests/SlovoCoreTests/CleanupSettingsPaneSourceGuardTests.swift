import Foundation
import Testing

// The Cleanup pane's off-state contract (spec): master toggle first, disabled
// when no key; dependent sections disabled while effectively off; the API-key
// section NEVER disabled by availability (it is the way out of the no-key state);
// the status line comes from CleanupAvailability, never a re-derived string.
@Suite("Cleanup settings pane source guard")
struct CleanupSettingsPaneSourceGuardTests {
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static func paneSource() throws -> String {
        try String(
            contentsOf: packageRoot.appending(path: "Sources/slovo/Settings/CleanupSettingsPane.swift"),
            encoding: .utf8
        )
    }

    /// Stated sensitivity: gate the toggle on `isOn` instead of
    /// `isToggleEnabled`, or drop the disabled modifier → RED.
    @Test
    func masterToggleIsGatedOnToggleEnabled() throws {
        let source = try Self.paneSource()
        #expect(source.contains(#"Toggle("Clean up dictation""#))
        #expect(source.contains(".disabled(!availability.isToggleEnabled)"))
    }

    /// Stated sensitivity: hardcode a status string in the pane → RED.
    @Test
    func statusLineComesFromCleanupAvailability() throws {
        let source = try Self.paneSource()
        #expect(source.contains("availability.settingsStatusLine"))
        #expect(!source.contains("Cleanup is off"), "copy lives in CleanupAvailability, not the pane")
    }

    /// Stated sensitivity: change the dependent-control count (forget a control, or
    /// gate the wrong number) → the `== 4` assert reddens; add
    /// `.disabled(!availability.isOn)` to the API-key section (the exact mutation this
    /// guards) → the key-section assert reddens. The key-section check targets
    /// availability gating specifically — the Save button's own empty-field
    /// `.disabled(trimmedApiKey.isEmpty)` is a legitimate, unrelated guard and must
    /// not count. The dependent controls are now gated per-row (the model picker, the
    /// writing-style row, the translate row, and the spell-check-hints section), since
    /// the model row alone replaces its control with the add-key affordance in the
    /// no-key state and so cannot ride a section-level gate.
    @Test
    func dependentSectionsDisabledAndKeySectionExempt() throws {
        let source = try Self.paneSource()
        let disabledCount = source.components(separatedBy: ".disabled(!availability.isOn)").count - 1
        #expect(disabledCount == 4, "model picker, writing style, translate, spell-check hints; found \(disabledCount)")
        guard let apiStart = source.range(of: "private var apiKeySection") else {
            Issue.record("apiKeySection not found")
            return
        }
        // Scope the scan to the section body — from its declaration to the
        // next `private var` (or EOF). A fixed-length window goes blind past
        // its edge and bleeds into sibling sections.
        let tail = source[apiStart.upperBound...]
        let apiBody = tail.range(of: "\n    private var").map { tail[..<$0.lowerBound] } ?? tail
        #expect(!apiBody.contains(".disabled(!availability"), "the key section must never be gated by availability")
    }

    /// Selector-replaced-in-offNoKey: with no key there is nothing to select, so the
    /// model row renders the add-key affordance IN PLACE OF the picker, and that
    /// affordance focuses the key field below (field focus achieved on the pane).
    /// Stated sensitivity: drop the `availability == .offNoKey` branch (always show
    /// the picker), drop the add-key button, or drop the field-focus wiring → RED.
    @Test
    func modelSelectorReplacedByAddKeyInNoKeyState() throws {
        let source = try Self.paneSource()
        let modelRowBody = try Self.bodyOf("private var modelRow", in: source)
        #expect(modelRowBody.contains("if availability == .offNoKey"),
                "the model row must branch on the no-key state")
        #expect(modelRowBody.contains("addKeyButton"),
                "the no-key branch must render the add-key affordance instead of the picker")
        #expect(modelRowBody.contains("modelPicker"),
                "the key-present branch must still render the model picker")
        let addKeyBody = try Self.bodyOf("private var addKeyButton", in: source)
        #expect(addKeyBody.contains(#"Button("Add OpenRouter Key…")"#),
                "the add-key affordance keeps its pinned copy")
        #expect(addKeyBody.contains("keyFieldFocused = true"),
                "the add-key affordance must focus the key field")
        #expect(source.contains(".focused($keyFieldFocused)"),
                "the key field must be a focus target for the add-key affordance")
    }

    /// Selector-disabled-in-offByChoice: when a key is present but cleanup is off the
    /// model picker stays visible but disabled — there IS a selection, it just cannot
    /// take effect. The picker's key-present branch carries the availability gate.
    /// Stated sensitivity: drop the picker's `.disabled(!availability.isOn)` → RED.
    @Test
    func modelPickerIsDisabledWhenCleanupOff() throws {
        let source = try Self.paneSource()
        let modelRowBody = try Self.bodyOf("private var modelRow", in: source)
        #expect(modelRowBody.contains(".disabled(!availability.isOn)"),
                "the model picker must be gated off when cleanup is off with a key present")
    }

    /// Extracts the body of a `private var` declaration — from its head to the next
    /// `private var` (or EOF) — so a guard scoped to one computed view cannot be
    /// satisfied by a token living in a sibling.
    private static func bodyOf(_ head: String, in source: String) throws -> Substring {
        guard let start = source.range(of: head) else {
            throw Failure.notFound(head)
        }
        let tail = source[start.upperBound...]
        return tail.range(of: "\n    private var").map { tail[..<$0.lowerBound] } ?? tail
    }

    private enum Failure: Error { case notFound(String) }
}
