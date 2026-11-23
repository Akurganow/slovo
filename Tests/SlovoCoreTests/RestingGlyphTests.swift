import Testing

import SlovoCore

@Suite("RestingGlyph derivation")
struct RestingGlyphTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let isPipelineActive: Bool
        let isShowingBriefStatus: Bool
        let isGlyphHeldByNotice: Bool
        let gate: ModelGate
        let expected: RestingGlyph

        var testDescription: String {
            "pipeline \(isPipelineActive), brief \(isShowingBriefStatus), held \(isGlyphHeldByNotice), \(gate) -> \(expected)"
        }
    }

    /// Every input of the decision (2 x 2 x 2 x 3) against its output: a flash
    /// leaves the glyph alone; a live dictation leaves it to a notice that holds it
    /// and otherwise gets it back as the hold; with no dictation the hold flag is
    /// ignored, a loading gate shows the loading glyph, and onboarding or an open
    /// gate shows idle.
    /// Stated sensitivity: drop the flash term or the held term, return `.leave`
    /// for every live dictation, let the held flag matter with no dictation, treat
    /// `.notGated` or `.open` as `.loading`, or swap the `.loading` and `.idle`
    /// results → RED.
    static let rows: [Row] = [
        Row(isPipelineActive: false, isShowingBriefStatus: false, isGlyphHeldByNotice: false, gate: .notGated, expected: .idle),
        Row(isPipelineActive: false, isShowingBriefStatus: false, isGlyphHeldByNotice: false, gate: .loading, expected: .loading),
        Row(isPipelineActive: false, isShowingBriefStatus: false, isGlyphHeldByNotice: false, gate: .open, expected: .idle),
        Row(isPipelineActive: false, isShowingBriefStatus: false, isGlyphHeldByNotice: true, gate: .notGated, expected: .idle),
        Row(isPipelineActive: false, isShowingBriefStatus: false, isGlyphHeldByNotice: true, gate: .loading, expected: .loading),
        Row(isPipelineActive: false, isShowingBriefStatus: false, isGlyphHeldByNotice: true, gate: .open, expected: .idle),
        Row(isPipelineActive: false, isShowingBriefStatus: true, isGlyphHeldByNotice: false, gate: .notGated, expected: .leave),
        Row(isPipelineActive: false, isShowingBriefStatus: true, isGlyphHeldByNotice: false, gate: .loading, expected: .leave),
        Row(isPipelineActive: false, isShowingBriefStatus: true, isGlyphHeldByNotice: false, gate: .open, expected: .leave),
        Row(isPipelineActive: false, isShowingBriefStatus: true, isGlyphHeldByNotice: true, gate: .notGated, expected: .leave),
        Row(isPipelineActive: false, isShowingBriefStatus: true, isGlyphHeldByNotice: true, gate: .loading, expected: .leave),
        Row(isPipelineActive: false, isShowingBriefStatus: true, isGlyphHeldByNotice: true, gate: .open, expected: .leave),
        Row(isPipelineActive: true, isShowingBriefStatus: false, isGlyphHeldByNotice: false, gate: .notGated, expected: .hold),
        Row(isPipelineActive: true, isShowingBriefStatus: false, isGlyphHeldByNotice: false, gate: .loading, expected: .hold),
        Row(isPipelineActive: true, isShowingBriefStatus: false, isGlyphHeldByNotice: false, gate: .open, expected: .hold),
        Row(isPipelineActive: true, isShowingBriefStatus: false, isGlyphHeldByNotice: true, gate: .notGated, expected: .leave),
        Row(isPipelineActive: true, isShowingBriefStatus: false, isGlyphHeldByNotice: true, gate: .loading, expected: .leave),
        Row(isPipelineActive: true, isShowingBriefStatus: false, isGlyphHeldByNotice: true, gate: .open, expected: .leave),
        Row(isPipelineActive: true, isShowingBriefStatus: true, isGlyphHeldByNotice: false, gate: .notGated, expected: .leave),
        Row(isPipelineActive: true, isShowingBriefStatus: true, isGlyphHeldByNotice: false, gate: .loading, expected: .leave),
        Row(isPipelineActive: true, isShowingBriefStatus: true, isGlyphHeldByNotice: false, gate: .open, expected: .leave),
        Row(isPipelineActive: true, isShowingBriefStatus: true, isGlyphHeldByNotice: true, gate: .notGated, expected: .leave),
        Row(isPipelineActive: true, isShowingBriefStatus: true, isGlyphHeldByNotice: true, gate: .loading, expected: .leave),
        Row(isPipelineActive: true, isShowingBriefStatus: true, isGlyphHeldByNotice: true, gate: .open, expected: .leave),
    ]

    @Test(arguments: rows)
    func resolvesEveryInput(row: Row) {
        let derived = RestingGlyph.derive(
            isPipelineActive: row.isPipelineActive,
            isShowingBriefStatus: row.isShowingBriefStatus,
            isGlyphHeldByNotice: row.isGlyphHeldByNotice,
            gate: row.gate
        )
        #expect(derived == row.expected)
    }
}
