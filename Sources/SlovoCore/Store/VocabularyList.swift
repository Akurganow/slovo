/// The Vocabulary pane's mirror of the vocabulary table.
public enum VocabularyList: Equatable, Sendable {
    /// The database did not open or could not be read: dictation runs without vocabulary.
    case unavailable
    case available([VocabularyRecord])

    /// Whether terms can be added or removed.
    public var isEditable: Bool {
        if case .available = self { return true }
        return false
    }

    /// The terms to list: empty while unavailable.
    public var records: [VocabularyRecord] {
        if case .available(let rows) = self { return rows }
        return []
    }

    /// One read of the table; nil means there is no database.
    public init(reading read: (() throws -> [VocabularyRecord])?) {
        guard let read, let rows = try? read() else {
            self = .unavailable
            return
        }
        self = .available(rows)
    }
}
