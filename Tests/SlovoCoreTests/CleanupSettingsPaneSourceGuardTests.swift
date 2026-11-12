import Foundation
import Testing

// The Cleanup pane's off-state contract (spec): master toggle first, disabled
// when no key; dependent sections disabled while effectively off; the API-key
// section NEVER disabled by availability (it is the way out of the no-key state);
// the status line comes from CleanupAvailability, never a re-derived string.
// No test target depends on the `slovo` executable, so these guards read the pane's source.
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
        let apiBody = try SourceText.block(after: "private var apiKeySection", in: source)
        #expect(!apiBody.contains(".disabled(!availability"), "the key section must never be gated by availability")
    }

    /// With no key the model picker grays exactly like writing style and translate:
    /// it rides the cleanupSection's availability gate, and the model row holds no
    /// branch on key presence.
    /// Stated sensitivity: read the availability, the pane's `hasKey` (derived from it), `offNoKey`
    /// or the store's key presence inside the model row, reintroduce an
    /// `availability == .offNoKey` branch anywhere in the pane, or drop the
    /// cleanupSection availability gate (so the model no longer grays in no-key) → RED.
    /// A marker that goes missing or changes order fails this test with the missing
    /// marker's text.
    @Test
    func modelSelectorGraysInOffNoKeyLikeTheOtherDependentRows() throws {
        let source = try SourceText.code(Self.panePath)
        #expect(!source.contains("availability == .offNoKey"),
                "the pane must not special-case the no-key state with an active control")
        let modelRow = try SourceText.block(after: "var modelRow", in: source)
        for read in ["availability", "hasKey", "offNoKey", "isOpenRouterKeyPresent"] {
            #expect(modelRow.range(of: read, options: .caseInsensitive) == nil,
                    "the model row must not read key presence: \(read)")
        }

        let bodyBlock = try SourceText.block(after: "var body", in: source)
        let cleanupGate = try SourceText.slice(of: bodyBlock, from: "cleanupSection", to: "apiKeySection")
        #expect(cleanupGate.contains(".disabled(!availability.isOn)"),
                "the Cleanup section must be availability-gated so the model grays in the no-key state")
    }
}
