import SlovoCore

extension AppDelegate {
    static func title(for status: StatusMessage) -> String {
        switch status {
        case .preparingSpeechModel:
            return "Preparing Speech Model"
        case .cleanupDeclinedInsertedAsSpoken:
            return "Inserted As Spoken"
        case .cleanupUnavailableInsertedAsSpoken:
            return "Inserted As Spoken"
        case .accessibilityDenied:
            return "Accessibility Denied"
        case .missingKey:
            return "Missing Cleanup Key"
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
            // exhaustiveness and is never placed on the status line (see showStatus).
            return "No Speech"
        }
    }
}
