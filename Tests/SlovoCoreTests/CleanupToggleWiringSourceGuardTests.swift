import Foundation
import Testing

// The recording glyph reads cleanup availability in one place: both sequencer arms
// route the glyph through `applyRecordingGlyph`, which reads the store.
// AppDelegate is in the executable "slovo" target, which no test target imports
// (Package.swift, SlovoCoreTests dependencies; docs/references/testing-swift.md
// section 1.6), so these guards read source.
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
        guard let downArm = source.range(of: "case .down(let mode):"),
              let latchArm = source.range(of: "case .translateLatched:"),
              let upArm = source.range(of: "case .up(let mode):")
        else {
            Issue.record("sequencer arms not found")
            return
        }
        let downBody = source[downArm.lowerBound..<latchArm.lowerBound]
        let latchBody = source[latchArm.lowerBound..<upArm.lowerBound]

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
