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

    /// Stated sensitivity: change the dependent-section count (forget a section, or
    /// gate the wrong number) → the `== 2` assert reddens; add
    /// `.disabled(!availability.isOn)` to the API-key section (the exact mutation this
    /// guards) → the key-section assert reddens. The key-section check targets
    /// availability gating specifically — the Save button's own empty-field
    /// `.disabled(trimmedApiKey.isEmpty)` is a legitimate, unrelated guard and must
    /// not count.
    @Test
    func dependentSectionsDisabledAndKeySectionExempt() throws {
        let source = try Self.paneSource()
        let disabledCount = source.components(separatedBy: ".disabled(!availability.isOn)").count - 1
        #expect(disabledCount == 2, "cleanupSection and spellCheckHintsSection; found \(disabledCount)")
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
}
