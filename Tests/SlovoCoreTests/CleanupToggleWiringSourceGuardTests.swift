import Foundation
import Testing

// The recording glyph reads cleanup availability in one place: both sequencer arms
// route the glyph through `applyRecordingGlyph`, which reads the store.
// No test target depends on the `slovo` executable, so these guards read AppDelegate's source.
@Suite("Cleanup toggle wiring source guard")
struct CleanupToggleWiringSourceGuardTests {
    /// Availability stays out of the sequencer arms: `applyRecordingGlyph` reads
    /// `store.state.cleanupAvailability.isOn` once, as the derivation argument, so no
    /// arm carries a separate gate read that a mutant could leave dead while still
    /// ungating the paint. Both arms route the glyph through it. The rule itself (raw
    /// wins over translate while cleanup is off) is
    /// `MenuBarGlyphTests.recordingGlyphModeDerivesFromModeAndAvailability`.
    /// Stated sensitivity: read `cleanupAvailability` in either arm, or drop an arm's
    /// `applyRecordingGlyph` routing → RED.
    @Test
    func sequencerArmsReadNoAvailabilityAndPaintThroughApplyRecordingGlyph() throws {
        let source = try SourceText.code("Sources/slovo/AppDelegate.swift")
        let downBody = try SourceText.slice(of: source, from: "case .down(let mode):", to: "case .translateLatched:")
        let latchBody = try SourceText.slice(of: source, from: "case .translateLatched:", to: "case .up(let mode):")

        #expect(!downBody.contains("cleanupAvailability"),
                "the .down arm must not read availability; it is consumed once inside applyRecordingGlyph")
        #expect(!latchBody.contains("cleanupAvailability"),
                "the .translateLatched arm must not read availability; it is consumed once inside applyRecordingGlyph")
        #expect(downBody.contains("applyRecordingGlyph(mode)"),
                "the .down arm must route the glyph through applyRecordingGlyph")
        #expect(latchBody.contains("applyRecordingGlyph(.translate)"),
                "the translate latch must route the glyph through applyRecordingGlyph")
    }
}
