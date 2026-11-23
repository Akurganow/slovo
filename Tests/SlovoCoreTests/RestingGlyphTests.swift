import Testing

import SlovoCore

@Suite("RestingGlyph derivation")
struct RestingGlyphTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let isShowingBriefStatus: Bool
        let liveDictation: LiveDictation?
        let gate: ModelGate
        let expected: RestingGlyph

        var testDescription: String {
            "brief \(isShowingBriefStatus), live \(String(describing: liveDictation)), \(gate) -> \(expected)"
        }
    }

    /// Every input of the decision (2 x 3 x 3) against its output, plus a recording
    /// hold: a flash leaves the glyph alone; a notice that ended the dictation
    /// holds it; any other live dictation gets it back as the hold, whatever the
    /// gate; with no dictation a loading gate shows the loading glyph, and
    /// onboarding or an open gate shows idle.
    /// Stated sensitivity: drop the flash term, return `.hold` for a held notice,
    /// return `.leave` for a hold, treat `.notGated` or `.open` as `.loading`, or
    /// swap the `.loading` and `.idle` results → RED.
    static let rows: [Row] = [
        Row(isShowingBriefStatus: false, liveDictation: nil, gate: .notGated, expected: .idle),
        Row(isShowingBriefStatus: false, liveDictation: nil, gate: .loading, expected: .loading),
        Row(isShowingBriefStatus: false, liveDictation: nil, gate: .open, expected: .idle),
        Row(isShowingBriefStatus: false, liveDictation: .hold(.processing), gate: .notGated, expected: .hold),
        Row(isShowingBriefStatus: false, liveDictation: .hold(.processing), gate: .loading, expected: .hold),
        Row(isShowingBriefStatus: false, liveDictation: .hold(.processing), gate: .open, expected: .hold),
        Row(isShowingBriefStatus: false, liveDictation: .heldByNotice, gate: .notGated, expected: .leave),
        Row(isShowingBriefStatus: false, liveDictation: .heldByNotice, gate: .loading, expected: .leave),
        Row(isShowingBriefStatus: false, liveDictation: .heldByNotice, gate: .open, expected: .leave),
        Row(isShowingBriefStatus: true, liveDictation: nil, gate: .notGated, expected: .leave),
        Row(isShowingBriefStatus: true, liveDictation: nil, gate: .loading, expected: .leave),
        Row(isShowingBriefStatus: true, liveDictation: nil, gate: .open, expected: .leave),
        Row(isShowingBriefStatus: true, liveDictation: .hold(.processing), gate: .notGated, expected: .leave),
        Row(isShowingBriefStatus: true, liveDictation: .hold(.processing), gate: .loading, expected: .leave),
        Row(isShowingBriefStatus: true, liveDictation: .hold(.processing), gate: .open, expected: .leave),
        Row(isShowingBriefStatus: true, liveDictation: .heldByNotice, gate: .notGated, expected: .leave),
        Row(isShowingBriefStatus: true, liveDictation: .heldByNotice, gate: .loading, expected: .leave),
        Row(isShowingBriefStatus: true, liveDictation: .heldByNotice, gate: .open, expected: .leave),
        Row(isShowingBriefStatus: false, liveDictation: .hold(.recording(.translate)), gate: .open, expected: .hold),
    ]

    @Test(arguments: rows)
    func resolvesEveryInput(row: Row) {
        let derived = RestingGlyph.derive(
            isShowingBriefStatus: row.isShowingBriefStatus,
            liveDictation: row.liveDictation,
            gate: row.gate
        )
        #expect(derived == row.expected)
    }
}
