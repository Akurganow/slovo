public enum MenuBarGlyphTint: Equatable, Sendable {
    case normal
    case error
}

public enum MenuBarGlyph {
    public static func forState(_ state: DictationState) -> Character {
        switch state {
        case .recording:
            return forRecording(mode: .plain)
        case .idle:
            return "\u{2C14}"
        case .processing:
            return "\u{2C04}"
        }
    }

    /// The recording glyph for a session's mode: Zemlja Ⰸ (U+2C08, the Glagolitic
    /// "Z" for "запись") while plainly dictating, Pokoji Ⱂ (U+2C12) while a translate
    /// hold is active, so the menu bar tells the two apart at a glance.
    public static func forRecording(mode: DictationMode) -> Character {
        switch mode {
        case .plain:
            return "\u{2C08}"
        case .translate:
            return "\u{2C12}"
        }
    }

    public static func forStatus(_ status: StatusMessage) -> Character? {
        switch status {
        case .cleanupUnavailableInsertedAsSpoken:
            return "\u{2C11}"
        case .preparingSpeechModel:
            return "\u{2C06}"
        case .cleanupDeclinedInsertedAsSpoken,
             .accessibilityDenied,
             .missingKey,
             .transcriptionFailed,
             .secureFieldActive,
             .injectionFailed,
             .microphoneUnavailable,
             .cleanupFailed:
            return nil
        }
    }

    public static func tint(forStatus status: StatusMessage) -> MenuBarGlyphTint {
        switch status {
        case .cleanupUnavailableInsertedAsSpoken:
            return .error
        case .preparingSpeechModel,
             .cleanupDeclinedInsertedAsSpoken,
             .accessibilityDenied,
             .missingKey,
             .transcriptionFailed,
             .secureFieldActive,
             .injectionFailed,
             .microphoneUnavailable,
             .cleanupFailed:
            return .normal
        }
    }
}

public final class DictationHistory {
    private let capacity: Int
    private var storedEntries: [String] = []

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
    }

    public func record(_ text: String) {
        guard capacity > 0 else { return }
        storedEntries.insert(text, at: 0)
        if storedEntries.count > capacity {
            storedEntries.removeLast(storedEntries.count - capacity)
        }
    }

    public var entries: [String] {
        storedEntries
    }
}
