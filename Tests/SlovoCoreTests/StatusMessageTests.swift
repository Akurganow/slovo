import Testing

import SlovoCore

@Suite("StatusMessage classification")
struct StatusMessageTests {
    private static let outputNotices: [StatusMessage] = [.outputMuteFailed, .outputRestoreFailed]

    private static let otherNotices: [StatusMessage] = [
        .preparingSpeechModel,
        .cleanupUnavailableInsertedAsSpoken,
        .accessibilityDenied,
        .transcriptionFailed,
        .secureFieldActive,
        .injectionFailed,
        .microphoneUnavailable,
        .noSpeechDetected,
    ]

    /// A failed mute or restore is a failure that keeps its row and gives the
    /// glyph back after its flash, since the dictation goes on.
    /// Stated sensitivity: `holdsGlyph` true for either output notice (the glyph
    /// would stay red for the rest of the hold), or either one not a failure or
    /// not persistent → RED.
    @Test(arguments: outputNotices)
    func outputNoticesFailKeepTheirRowAndGiveTheGlyphBack(status: StatusMessage) {
        #expect(status.isFailureNotice)
        #expect(status.isPersistentNotice)
        #expect(!status.holdsGlyph)
    }

    /// Every other notice holds the glyph exactly when it keeps the status line.
    /// Stated sensitivity: `holdsGlyph` false for a persistent or sad-to-fail
    /// notice, or true for a passing one → RED.
    @Test(arguments: otherNotices)
    func otherNoticesHoldTheGlyphWhenTheyKeepTheLine(status: StatusMessage) {
        #expect(status.holdsGlyph == (status.isPersistentNotice || status.isSadToFailNotice))
    }
}
