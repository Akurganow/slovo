import Foundation
import Testing

import SlovoCore

// Menu-bar logic only. Real NSStatusItem/NSImage rendering and font fallback are
// out of scope here; this slice locks state mapping plus the local-only history
// model that the popover will read in-process.
@Suite("MenuBarController logic")
struct MenuBarControllerTests {
    private static let sentinel = "S3NT1NEL-HISTORY-51c07e9b-DO-NOT-LOG"

    /// The recording state maps to Cherv Ⱍ (U+2C1D, the Glagolitic "чистота"/clean
    /// sense — cleanup will run), which REPLACES the old catch-all Zemlja Ⰸ now that
    /// recording is a mode family; NOT the inherited Heru U+2C18 typo.
    /// Stated sensitivity: revert the recording state to Zemlja U+2C08 (or any other
    /// codepoint) → RED.
    @Test
    func glyphMappingUsesDistinctGlyphsForLiveStates() {
        #expect(MenuBarGlyph.forState(.recording) == "\u{2C1D}")
        #expect(MenuBarGlyph.forState(.idle) == "\u{2C14}")
        #expect(MenuBarGlyph.forState(.processing) == "\u{2C04}")
    }

    /// The recording glyph is a fully semantic three-letter family varying on one
    /// dimension (the letter): Cherv Ⱍ (U+2C1D) clean, Glagoli Ⰳ (U+2C03) raw,
    /// Pokoji Ⱂ (U+2C12) translate — all distinct — and the default recording state
    /// maps to the clean glyph (one source of truth).
    /// Stated sensitivity: revert clean to Zemlja U+2C08, map raw to the clean glyph
    /// (collapsing the family to two letters), or move translate off Pokoji → RED.
    @Test
    func recordingGlyphFamilyMapsEachModeToItsLetter() {
        #expect(MenuBarGlyph.forRecording(mode: .clean) == "\u{2C1D}")
        #expect(MenuBarGlyph.forRecording(mode: .raw) == "\u{2C03}")
        #expect(MenuBarGlyph.forRecording(mode: .translate) == "\u{2C12}")

        let glyphs: Set<Character> = [
            MenuBarGlyph.forRecording(mode: .clean),
            MenuBarGlyph.forRecording(mode: .raw),
            MenuBarGlyph.forRecording(mode: .translate),
        ]
        #expect(glyphs.count == 3, "each recording mode must have its own distinct letter")
        #expect(MenuBarGlyph.forState(.recording) == MenuBarGlyph.forRecording(mode: .clean))
    }

    /// The recording-glyph mode is DERIVED from the latched dictation mode and
    /// cleanup availability — raw is the availability axis, not a `DictationMode`.
    /// Raw wins whenever cleanup is off (even with Control latched: a translate hold
    /// cannot run without cleanup); with cleanup on, translate marks a translate
    /// latch and clean marks a plain hold.
    /// Stated sensitivity: yield `.translate` for a translate hold while cleanup is
    /// off (must be `.raw`), yield anything but `.raw` when cleanup is off, or swap
    /// the on-mode results → RED.
    @Test
    func recordingGlyphModeDerivesFromModeAndAvailability() {
        #expect(MenuBarGlyph.recordingGlyphMode(mode: .plain, isCleanupOn: true) == .clean)
        #expect(MenuBarGlyph.recordingGlyphMode(mode: .translate, isCleanupOn: true) == .translate)
        #expect(MenuBarGlyph.recordingGlyphMode(mode: .plain, isCleanupOn: false) == .raw)
        #expect(MenuBarGlyph.recordingGlyphMode(mode: .translate, isCleanupOn: false) == .raw)
    }

    /// Stated sensitivity: reuse the processing glyph for cleanup degradation or
    /// forget the error tint -> the status bar cannot tell "inserted as spoken"
    /// from normal processing.
    @Test
    func cleanupUnavailableUsesSadToFailGlyphAndErrorTint() {
        #expect(MenuBarGlyph.forStatus(.cleanupUnavailableInsertedAsSpoken) == "\u{2C11}")
        #expect(MenuBarGlyph.tint(forStatus: .cleanupUnavailableInsertedAsSpoken) == .error)
    }

    /// The empty-result (no speech) surface reuses the red failure glyph Ⱁ (U+2C11)
    /// with the error tint — the spec's "brief red failure glyph" for a silent hold.
    /// Stated sensitivity: return nil for `.noSpeechDetected` (dropping it into the
    /// no-glyph group), a different codepoint, or a `.normal` tint → RED.
    @Test
    func noSpeechDetectedUsesFailureGlyphAndErrorTint() {
        #expect(MenuBarGlyph.forStatus(.noSpeechDetected) == "\u{2C11}")
        #expect(MenuBarGlyph.tint(forStatus: .noSpeechDetected) == .error)
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
