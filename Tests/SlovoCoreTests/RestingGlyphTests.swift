import Testing

import SlovoCore

@Suite("RestingGlyph derivation")
struct RestingGlyphTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let isPipelineActive: Bool
        let isShowingBriefStatus: Bool
        let gate: ModelGate
        let expected: RestingGlyph

        var testDescription: String {
            "pipeline \(isPipelineActive), brief \(isShowingBriefStatus), \(gate) -> \(expected)"
        }
    }

    /// Every input of the decision (2 x 2 x 3) against its output: either latch
    /// leaves the glyph alone; otherwise only a loading gate shows the loading
    /// glyph, and onboarding or an open gate shows idle.
    /// Stated sensitivity: drop either latch term, treat `.notGated` or `.open` as
    /// `.loading`, or swap the `.loading` and `.idle` results → RED.
    static let rows: [Row] = [
        Row(isPipelineActive: false, isShowingBriefStatus: false, gate: .notGated, expected: .idle),
        Row(isPipelineActive: false, isShowingBriefStatus: false, gate: .loading, expected: .loading),
        Row(isPipelineActive: false, isShowingBriefStatus: false, gate: .open, expected: .idle),
        Row(isPipelineActive: true, isShowingBriefStatus: false, gate: .notGated, expected: .leave),
        Row(isPipelineActive: true, isShowingBriefStatus: false, gate: .loading, expected: .leave),
        Row(isPipelineActive: true, isShowingBriefStatus: false, gate: .open, expected: .leave),
        Row(isPipelineActive: false, isShowingBriefStatus: true, gate: .notGated, expected: .leave),
        Row(isPipelineActive: false, isShowingBriefStatus: true, gate: .loading, expected: .leave),
        Row(isPipelineActive: false, isShowingBriefStatus: true, gate: .open, expected: .leave),
        Row(isPipelineActive: true, isShowingBriefStatus: true, gate: .notGated, expected: .leave),
        Row(isPipelineActive: true, isShowingBriefStatus: true, gate: .loading, expected: .leave),
        Row(isPipelineActive: true, isShowingBriefStatus: true, gate: .open, expected: .leave),
    ]

    @Test(arguments: rows)
    func resolvesEveryInput(row: Row) {
        let derived = RestingGlyph.derive(
            isPipelineActive: row.isPipelineActive,
            isShowingBriefStatus: row.isShowingBriefStatus,
            gate: row.gate
        )
        #expect(derived == row.expected)
    }
}
