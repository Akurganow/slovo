import Testing

@testable import SlovoCore

@Suite("Vocabulary list")
struct VocabularyListTests {
    private struct ReadFailed: Error {}

    private static let rows = [
        VocabularyRecord(term: "GitHub", category: "tech"),
        VocabularyRecord(term: "OAuth", category: "tech"),
    ]

    /// Stated sensitivity: map a missing database to `.available([])` → RED.
    @Test
    func noDatabaseIsUnavailable() {
        let list = VocabularyList(reading: nil)
        #expect(list == .unavailable)
        #expect(!list.isEditable)
        #expect(list.records.isEmpty)
    }

    /// Stated sensitivity: map a throwing read to `.available([])` → RED.
    @Test
    func aFailedReadIsUnavailable() {
        let list = VocabularyList(reading: { throw ReadFailed() })
        #expect(list == .unavailable)
        #expect(!list.isEditable)
    }

    /// An empty table is a real, editable state, distinct from an unreadable one.
    @Test
    func anEmptyTableIsAvailable() {
        let list = VocabularyList(reading: { [] })
        #expect(list == .available([]))
        #expect(list.isEditable)
        #expect(list.records.isEmpty)
    }

    /// Stated sensitivity: report `isEditable` true for `.unavailable`, or drop the
    /// rows from `records` → RED.
    @Test
    func rowsAreAvailableAndListed() {
        let list = VocabularyList(reading: { Self.rows })
        #expect(list == .available(Self.rows))
        #expect(list.isEditable)
        #expect(list.records == Self.rows)
    }
}
