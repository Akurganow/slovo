/// The dropdown's live status line as data. A menu rebuild renders it again, so
/// the line the user is looking at survives the rebuild.
public enum StatusLine: Equatable, Sendable {
    /// The hold-to-talk hint, which doubles as the idle status.
    case idle
    case recording
    case processing
    case message(StatusMessage)

    /// The row's text. `idleTrigger` is the key the idle hint tells the user to hold.
    public func text(idleTrigger: HotkeyTrigger) -> String {
        switch self {
        case .idle:
            return DictationMenu.idleStatusLine(trigger: idleTrigger)
        case .recording:
            return "Recording"
        case .processing:
            return "Processing"
        case .message(let message):
            return Self.title(for: message)
        }
    }

    private static func title(for message: StatusMessage) -> String {
        switch message {
        case .preparingSpeechModel:
            return "Preparing Speech Model"
        case .cleanupUnavailableInsertedAsSpoken:
            return "Inserted As Spoken"
        case .accessibilityDenied:
            return "Accessibility Denied"
        case .transcriptionFailed:
            return "Transcription Failed"
        case .secureFieldActive:
            return "Secure Field Active"
        case .injectionFailed:
            return "Insertion Failed"
        case .microphoneUnavailable:
            return "Microphone Unavailable"
        case .cleanupFailed:
            return "Cleanup Failed"
        case .noSpeechDetected:
            // The empty-result surface is glyph-only; this title exists for switch
            // exhaustiveness and is never placed on the status line (see
            // AppDelegate.showStatus).
            return "No Speech"
        }
    }
}
