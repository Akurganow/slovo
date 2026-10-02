import Testing

import SlovoCore

// The status row's copy, owned by SlovoCore so a menu rebuild renders the line the
// user is looking at.
@Suite("Status line")
struct StatusLineTests {
    /// Each status message renders its fixed title.
    /// Stated sensitivity: change one title → RED; exactness is the requirement
    /// (the copy is user-facing).
    @Test
    func messagesKeepTheirTitles() {
        let titles: [(StatusMessage, String)] = [
            (.preparingSpeechModel, "Preparing Speech Model"),
            (.cleanupUnavailableInsertedAsSpoken, "Inserted As Spoken"),
            (.accessibilityDenied, "Accessibility Denied"),
            (.transcriptionFailed, "Transcription Failed"),
            (.secureFieldActive, "Secure Field Active"),
            (.injectionFailed, "Insertion Failed"),
            (.microphoneUnavailable, "Microphone Unavailable"),
            (.cleanupFailed, "Cleanup Failed"),
            (.noSpeechDetected, "No Speech"),
        ]
        for (message, title) in titles {
            #expect(StatusLine.message(message).text(idleTrigger: .fn) == title)
        }
    }

    /// The two progress words the row shows while a dictation runs. With
    /// `messagesKeepTheirTitles` it pins every non-idle line exactly.
    /// Stated sensitivity: add a "Status: " prefix, or change either word → RED.
    @Test
    func progressWordsKeepTheirCopy() {
        #expect(StatusLine.recording.text(idleTrigger: .fn) == "Recording")
        #expect(StatusLine.processing.text(idleTrigger: .fn) == "Processing")
    }

    /// The idle line IS the hold-to-talk hint, built from the configured key's
    /// display name, not its wire value.
    /// Stated sensitivity: render a fixed key, or the wire value → RED.
    @Test
    func idleLineUsesTriggerDisplayName() {
        #expect(StatusLine.idle.text(idleTrigger: .rightCommand) == "Hold Right ⌘ to talk")
        #expect(StatusLine.idle.text(idleTrigger: .rightOption) == "Hold Right ⌥ to talk")
        #expect(StatusLine.idle.text(idleTrigger: .leftOption) == "Hold Left ⌥ to talk")
        #expect(DictationMenu.idleStatusLine(trigger: .rightCommand) == "Hold Right ⌘ to talk")
    }
}
