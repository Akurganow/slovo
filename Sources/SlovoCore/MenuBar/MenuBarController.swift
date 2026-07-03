public enum MenuBarGlyphTint: Equatable, Sendable {
    case normal
    case error
}

public enum MenuBarGlyph {
    public static func forState(_ state: DictationState) -> Character {
        switch state {
        case .recording:
            return "\u{2C18}"
        case .idle:
            return "\u{2C14}"
        case .processing:
            return "\u{2C04}"
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
