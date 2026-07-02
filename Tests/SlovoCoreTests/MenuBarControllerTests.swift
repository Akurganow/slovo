import Foundation
import Testing

import SlovoCore

// Epic 09b — menu-bar logic only. Real NSStatusItem/NSImage rendering and font
// fallback are L4; this CI slice locks state mapping plus the local-only history
// model that the popover will read in-process.
@Suite("Epic 09b MenuBarController logic")
struct MenuBarControllerTests {
    private static let sentinel = "S3NT1NEL-HISTORY-51c07e9b-DO-NOT-LOG"

    @Test
    func glyphMappingUsesDistinctGlyphsForLiveStates() {
        #expect(MenuBarGlyph.forState(.recording) == "\u{2C18}")
        #expect(MenuBarGlyph.forState(.idle) == "\u{2C44}")
        #expect(MenuBarGlyph.forState(.processing) == "\u{2C34}")
    }

    /// Stated sensitivity: reuse the processing glyph for cleanup degradation or
    /// forget the error tint -> the status bar cannot tell "inserted as spoken"
    /// from normal processing.
    @Test
    func cleanupUnavailableUsesSadToFailGlyphAndErrorTint() {
        #expect(MenuBarGlyph.forStatus(.cleanupUnavailableInsertedAsSpoken) == "\u{2C11}")
        #expect(MenuBarGlyph.tint(forStatus: .cleanupUnavailableInsertedAsSpoken) == .error)
    }

    /// Model-loading must be visible as its own glyph, not silence: Zhivete Ⰶ
    /// with a normal (non-error) tint — loading is a state, not a failure.
    /// Stated sensitivity: returning the status to the nil-glyph group, a wrong
    /// character, or an error tint goes RED.
    @Test
    func preparingSpeechModelShowsZhiveteGlyph() {
        #expect(MenuBarGlyph.forStatus(.preparingSpeechModel) == "\u{2C06}")
        #expect(MenuBarGlyph.tint(forStatus: .preparingSpeechModel) == .normal)
    }

    /// Stated sensitivity: append oldest-first or forget to evict past capacity →
    /// the exact newest-first/capped sequence changes and this goes RED.
    @Test
    func historyIsNewestFirstAndCapped() {
        let history = DictationHistory(capacity: 2)

        history.record("first")
        history.record("second")
        history.record("third")

        #expect(history.entries == ["third", "second"])
    }

    @Test
    func zeroCapacityHistoryStoresNothing() {
        let history = DictationHistory(capacity: 0)

        history.record(Self.sentinel)

        #expect(history.entries.isEmpty)
    }

    /// Stated sensitivity: adding logging/egress dependencies to the history
    /// source violates the local-only contract and fails this source-level guard.
    @Test
    func historySourceHasNoLoggingOrEgressDependencies() throws {
        let source = try String(contentsOfFile: Self.menuBarSourcePath, encoding: .utf8)
        let forbiddenTokens = [
            "RedactionSafeLog",
            "Logger(",
            "import os",
            "URLSession",
            "Anthropic",
            "Cleaner",
        ]

        for token in forbiddenTokens {
            #expect(!source.contains(token), "history source must not depend on \(token)")
        }
    }

    private static var menuBarSourcePath: String {
        let testFile = URL(fileURLWithPath: "\(#filePath)")
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SlovoCore/MenuBar/MenuBarController.swift")
            .path
    }
}
