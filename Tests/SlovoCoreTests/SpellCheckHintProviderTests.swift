import Testing

import SlovoCore

@Suite("Spell-check hint language gating")
struct SpellCheckHintProviderTests {
    /// Stated sensitivity: removing the enabled-language filter (spec's
    /// language-mismatch degradation) lets a finding whose language is not enabled
    /// survive — this turns red.
    @Test
    func findingsFromDisabledLanguagesAreDropped() {
        let english = SpellFinding(token: "teh", guesses: ["the"])
        let russian = SpellFinding(token: "прьвет", guesses: ["привет"])
        let candidates = [
            (finding: english, language: "en"),
            (finding: russian, language: "ru"),
        ]

        let gated = SystemSpellCheckHintProvider.findingsWithEnabledLanguages(
            candidates,
            enabled: ["en-US"]
        )

        #expect(gated == [english], "only findings whose primary language is enabled survive; got \(gated)")
    }

    /// Stated sensitivity: comparing full codes instead of the primary subtag makes
    /// "en" fail to match an enabled "en-US" — this turns red.
    @Test
    func enabledLanguageMatchesByPrimarySubtag() {
        let finding = SpellFinding(token: "teh", guesses: ["the"])

        let gated = SystemSpellCheckHintProvider.findingsWithEnabledLanguages(
            [(finding: finding, language: "en")],
            enabled: ["en-GB", "ru-RU"]
        )

        #expect(gated == [finding])
    }

    /// Stated sensitivity: raising the findings cap (e.g. to 100_000) or removing
    /// the cap from the pure filter+cap pipeline lets all 20 synthetic findings
    /// through instead of 15 — this turns red.
    @Test
    func findingsAreCappedAtFifteen() {
        let candidates = (0..<20).map { index in
            (finding: SpellFinding(token: "tok\(index)", guesses: ["fix\(index)"]), language: "en")
        }

        let gated = SystemSpellCheckHintProvider.findingsWithEnabledLanguages(
            candidates,
            enabled: ["en-US"]
        )

        #expect(gated.count == 15, "the advisory spell pass is capped at 15 findings; got \(gated.count)")
        #expect(gated.first == candidates.first?.finding, "the cap must keep the EARLIEST findings")
    }
}
