import Foundation

public enum MenuBarGlyph {
    public static func forState(_ state: DictationState) -> Character {
        switch state {
        case .recording:
            return "\u{2C18}"
        case .idle, .processing:
            return "\u{2C44}"
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
