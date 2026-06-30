import Foundation
import Testing

import LoquiCore

// Epic 09b — menu-bar logic only. Real NSStatusItem/NSImage rendering and font
// fallback are L4; this CI slice locks state mapping plus the local-only history
// model that the popover will read in-process.
@Suite("Epic 09b MenuBarController logic")
struct MenuBarControllerTests {
    private static let sentinel = "S3NT1NEL-HISTORY-51c07e9b-DO-NOT-LOG"

    @Test
    func glyphMappingUsesRecordingGlyphOnlyWhileRecording() {
        #expect(MenuBarGlyph.forState(.recording) == "\u{2C18}")
        #expect(MenuBarGlyph.forState(.idle) == "\u{2C44}")
        #expect(MenuBarGlyph.forState(.processing) == "\u{2C44}")
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
            .appendingPathComponent("Sources/LoquiCore/MenuBar/MenuBarController.swift")
            .path
    }
}
