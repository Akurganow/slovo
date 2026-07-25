import Testing

import SlovoCore

// Pins the bundled XML example resource: that it parses at all, that it carries
// the language-verified content the prompts rely on, and that the translation
// side is keyed by language CODE. The XML file in the repo is the source of
// truth; these tests are what turns "resource missing / malformed / silently
// emptied" from a runtime degradation into a red CI.
@Suite("Prompt example catalog")
struct PromptExampleCatalogTests {
    /// Stated sensitivity: deleting the resource, breaking its XML, or renaming
    /// the root/section tags collapses the bundled catalog to empty → RED here.
    @Test
    func bundledCatalogParsesTheXmlResource() {
        let catalog = PromptExampleCatalog.bundled
        #expect(!catalog.cleanup.isEmpty, "the bundled cleanup example set must not be empty")
        #expect(!catalog.translation.isEmpty, "the bundled translation example sets must not be empty")
        for (code, pairs) in catalog.translation {
            #expect(!pairs.isEmpty, "target \(code) must not carry an empty example list")
        }
    }

    /// Stated sensitivity: dropping an example or reordering the head of the set
    /// (the canonical mic-check must stay first) reddens; the count pins silent
    /// truncation by a parser change.
    @Test
    func cleanupSetCarriesTheVerifiedExamples() {
        let cleanup = PromptExampleCatalog.bundled.cleanup
        #expect(cleanup.count == 27)
        #expect(cleanup.first?.transcript == "1 2 3 проверяем 1 2 3")
        #expect(cleanup.contains(PromptExample(
            transcript: "отправь отчёт в пятницу нет стой лучше в четверг",
            output: "Отправь отчёт в четверг."
        )), "the self-correction exemplar must survive")
        #expect(cleanup.contains(PromptExample(
            transcript: "запусти swift test и открой pull request",
            output: "Запусти swift test и открой pull request."
        )), "the verbatim-lowercase command exemplar must survive")
        #expect(cleanup.contains(PromptExample(
            transcript: "созвон перенесли на пятнадцать тридцать",
            output: "Созвон перенесли на 15:30."
        )), "the number-normalization exemplar must survive")
        #expect(cleanup.contains(PromptExample(
            transcript: "запиши формулу x равно y в квадрате плюс 1",
            output: "Запиши формулу: x = y² + 1."
        )), "the formula-with-lead-in exemplar must survive")
        // The tail examples are load-bearing via recency bias (the XML declares
        // them traps), so their ORDER is pinned, not just membership: a silent
        // mid-list shuffle that demotes a trap from the recency window reddens.
        // The last slot is the translate trap — the scariest silent failure.
        #expect(cleanup.suffix(4).map(\.output) == [
            "How do I roll back the last migration?",
            "Я запушил фикс в feature branch, но code review ещё не прошёл.",
            "Добавь unit test для HTTP client.",
            "Переведи release notes на английский и запушь PR в GitHub.",
        ], "tail order drifted")
    }

    /// The shared set is language-neutral notation rendered in both modes for
    /// every target. Stated sensitivity: dropping the section, an example, or
    /// mutating an output (e.g. adding a terminal period to a bare formula,
    /// capitalizing a variable) reddens on the exact-pair pins.
    @Test
    func sharedSetCarriesTheLanguageNeutralFormulaExemplars() {
        let shared = PromptExampleCatalog.bundled.shared
        #expect(shared.count == 4)
        #expect(shared.contains(PromptExample(
            transcript: "c equals a squared plus b squared",
            output: "c = a² + b²"
        )), "the bare-formula exemplar (no terminal period, no capitalization) must survive")
        #expect(shared.contains(PromptExample(
            transcript: "логарифм по основанию 2 от 3",
            output: "log₂(3)"
        )), "the logarithm-base exemplar must survive")
        #expect(shared.contains(PromptExample(
            transcript: "2x в квадрате равно y в квадрате минус y факториал",
            output: "2x² = y² − y!"
        )), "the factorial/power exemplar must survive")
        #expect(shared.contains(PromptExample(
            transcript: "y равно квадратный корень из x",
            output: "y = √x"
        )), "the square-root exemplar must survive")
    }

    /// The verified language core: every code here shipped only after independent
    /// language verification. Stated sensitivity: adding an unverified target,
    /// dropping a verified one, or keying by display name reddens.
    @Test
    func translationTargetsAreTheVerifiedCoreKeyedByCode() {
        let targets = Set(PromptExampleCatalog.bundled.translation.keys)
        #expect(targets == ["en", "ru", "es", "de", "fr", "pl", "uk", "fi", "zh", "ja", "hi", "ar"])
        #expect(PromptExampleCatalog.bundled.translation["en"]?.count == 4,
                "the primary en target carries the full behavioral set")
    }

    /// Stated sensitivity: swapping transcript/output tags in the parser, or
    /// losing non-Latin text in transit, reddens on this exact pair.
    @Test
    func parserPreservesTranscriptOutputPairing() {
        let english = PromptExampleCatalog.bundled.translation["en"]
        let question = english?.first { $0.transcript.hasPrefix("какой сейчас статус") }
        #expect(question?.output == "What's the current status of the authorization bug? Can you take a look at the logs?")
    }
}
