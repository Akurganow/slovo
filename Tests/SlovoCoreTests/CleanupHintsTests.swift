import Testing

import SlovoCore

@Suite("Cleanup hint value types")
struct CleanupHintsTests {
    /// Stated sensitivity: seeding the default init with a non-empty locale or a
    /// non-empty findings list (so "no hints" is no longer neutral) turns this red.
    @Test
    func emptyHintsAreTheNeutralDefault() {
        let empty = CleanupHints()

        #expect(empty.inputLocale == nil)
        #expect(empty.spellFindings.isEmpty)
        #expect(empty == CleanupHints(inputLocale: nil, spellFindings: []))
    }

    /// Stated sensitivity: dropping `Equatable` field-by-field comparison (e.g.
    /// ignoring `guesses`) makes two differing findings compare equal.
    @Test
    func findingsCompareByTokenAndGuesses() {
        let oneGuess = SpellFinding(token: "recieve", guesses: ["receive"])
        let twoGuesses = SpellFinding(token: "recieve", guesses: ["receive", "relieve"])

        #expect(oneGuess != twoGuesses)
        #expect(oneGuess == SpellFinding(token: "recieve", guesses: ["receive"]))
    }
}
