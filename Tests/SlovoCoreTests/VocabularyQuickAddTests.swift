import Testing

import SlovoCore

@Suite("Vocabulary quick-add parsing")
struct VocabularyQuickAddTests {
    /// Stated sensitivity: dropping the trim, the empty-fragment filter, or the
    /// comma split makes the exact expected array mismatch and this goes RED.
    @Test
    func splitsOnCommasTrimsAndDropsEmpties() {
        #expect(VocabularyQuickAdd.parseTerms(" GitHub,  OAuth ,,GraphQL, ") == ["GitHub", "OAuth", "GraphQL"])
    }

    /// Stated sensitivity: case-sensitive dedup (or no dedup) keeps the second
    /// "github" spelling and the expected single-element array mismatches.
    @Test
    func deduplicatesCaseInsensitivelyKeepingFirstSpelling() {
        #expect(VocabularyQuickAdd.parseTerms("GitHub, github, GITHUB") == ["GitHub"])
    }

    @Test
    func emptyInputYieldsNothing() {
        #expect(VocabularyQuickAdd.parseTerms("  ,, ").isEmpty)
        #expect(VocabularyQuickAdd.records(from: "  ").isEmpty)
    }

    /// Stated sensitivity: wrong category/source/weight constants or a lost term
    /// break the field-by-field expectations below.
    @Test
    func recordsCarryQuickAddDefaults() throws {
        let records = VocabularyQuickAdd.records(from: "GitHub, OAuth")
        try #require(records.count == 2)
        #expect(records.map(\.term) == ["GitHub", "OAuth"])
        for record in records {
            #expect(record.category == "term")
            #expect(record.source == "manual")
            #expect(record.weight == 3)
            #expect(record.expansion == nil)
        }
    }
}
