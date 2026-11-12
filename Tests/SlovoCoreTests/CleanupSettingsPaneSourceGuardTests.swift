import Foundation
import Testing

// The Cleanup pane's off-state contract (spec): master toggle first, disabled
// when no key; dependent sections disabled while effectively off; the API-key
// section NEVER disabled by availability (it is the way out of the no-key state);
// the status line comes from CleanupAvailability, never a re-derived string.
// The pane is in the executable "slovo" target, which no test target imports
// (Package.swift, SlovoCoreTests dependencies; docs/references/testing-swift.md
// section 1.6), so these guards read source.
@Suite("Cleanup settings pane source guard")
struct CleanupSettingsPaneSourceGuardTests {
    /// Read comment-stripped like every sibling source guard: a commented-out
    /// `.disabled(!availability.isOn)` must not inflate the dependent-section
    /// count below, and a token in documentation must not satisfy any pin.
    private static let panePath = "Sources/slovo/Settings/CleanupSettingsPane.swift"

    /// The title moved into the label builder — the status line is its subtitle Text,
    /// so the hint stays attached to the toggle instead of becoming its own row behind
    /// a divider — so the toggle is pinned by its binding form plus that title Text
    /// rather than by a `Toggle("…", isOn:)` string argument.
    /// Stated sensitivity: gate the toggle on `isOn` instead of `isToggleEnabled`, drop
    /// the disabled modifier, or drop the title from the label → RED.
    @Test
    func masterToggleIsGatedOnToggleEnabled() throws {
        let source = try SourceText.code(Self.panePath)
        #expect(source.contains("Toggle(isOn: Binding("))
        #expect(source.contains(#"Text("Clean up dictation")"#))
        #expect(source.contains(".disabled(!availability.isToggleEnabled)"))
    }

    /// Stated sensitivity: hardcode a status string in the pane → RED.
    @Test
    func statusLineComesFromCleanupAvailability() throws {
        let source = try SourceText.code(Self.panePath)
        #expect(source.contains("availability.settingsStatusLine"))
        #expect(!source.contains("Cleanup is off"), "copy lives in CleanupAvailability, not the pane")
    }

    /// Stated sensitivity: change the dependent-section count (forget a section, or
    /// gate the wrong number) → the `== 2` assert reddens; add
    /// `.disabled(!availability.isOn)` to the API-key section (the exact mutation this
    /// guards) → the key-section assert reddens. The key-section check targets
    /// availability gating specifically — the Save button's own empty-field
    /// `.disabled(trimmedApiKey.isEmpty)` is a legitimate, unrelated guard and must not
    /// count. The dependent controls ride two section-level gates: the whole Cleanup
    /// section (model, writing style, translate) and the spell-check-hints section.
    @Test
    func dependentSectionsDisabledAndKeySectionExempt() throws {
        let source = try SourceText.code(Self.panePath)
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

    /// With no key the model picker grays exactly like writing style and translate:
    /// it rides the cleanupSection's availability gate, and the model row holds no
    /// branch on key presence (an active control there was the removed add-key
    /// button's place).
    /// Stated sensitivity: put a branch on `offNoKey` or `hasKey` inside the model
    /// row, reintroduce an `availability == .offNoKey` branch anywhere in the pane, or
    /// drop the cleanupSection availability gate (so the model no longer grays in
    /// no-key) → RED.
    @Test
    func modelSelectorGraysInOffNoKeyLikeTheOtherDependentRows() throws {
        let source = try SourceText.code(Self.panePath)
        #expect(!source.contains("availability == .offNoKey"),
                "the pane must not special-case the no-key state with an active control")
        let modelRow = try Self.bodyOf("var modelRow", in: source)
        for token in ["offNoKey", "hasKey"] {
            #expect(!modelRow.contains(token), "the model row must not branch on key presence: \(token)")
        }

        let bodyBlock = try Self.bodyOf("var body", in: source)
        guard let cleanup = bodyBlock.range(of: "cleanupSection"),
              let api = bodyBlock.range(of: "apiKeySection")
        else {
            Issue.record("cleanupSection/apiKeySection not found in body")
            return
        }
        #expect(bodyBlock[cleanup.upperBound..<api.lowerBound].contains(".disabled(!availability.isOn)"),
                "the Cleanup section must be availability-gated so the model grays in the no-key state")
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
