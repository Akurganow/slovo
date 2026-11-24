import Testing

@testable import CleanupBenchmark

@Suite("Cleanup benchmark fuzzy score")
struct FuzzyScoreTests {
    /// Stated sensitivity: dropping the word sort in the wrapper's `token_sort_ratio`
    /// call scores swapped words below 100. Ids RapidFuzz would read as whitespace
    /// are caught by `missingCombiningMarkCostsOneCharacter`.
    @Test
    func swappedWordsScoreOne() {
        // The first text is the raw of sample `code-switching-clean-10` of
        // `Benchmarks/cleanup/slovo-cleanup-v1.json`; the second reorders its words.
        #expect(FuzzyScore.tokenSort("Проверь latency на staging.", "staging на проверь latency") == 1)
        #expect(FuzzyScore.tokenSort("a b", "b a") == 1)
    }

    /// Stated sensitivity: stripping combining marks while folding, or comparing
    /// Unicode scalars instead of `Character`s, makes a one-mark difference cost more
    /// than one id or none at all, so these scores leave their pinned values.
    @Test
    func missingCombiningMarkCostsOneCharacter() {
        // "غدًا" is three Characters, one of them a letter with its mark: two of
        // the three ids match, so ratio = 2 * 2 / (3 + 3).
        #expect(abs(FuzzyScore.tokenSort("غدا", "غدًا") - 2.0 / 3.0) < 1e-9)
        // "कि" is one Character (letter and vowel sign) and differs from "क".
        #expect(FuzzyScore.tokenSort("कि", "क") == 0)
    }

    /// Stated sensitivity: folding that keeps punctuation, casing or `ё`, or that
    /// drops a character other than punctuation, changes this exact-match pair.
    @Test
    func foldingIgnoresCasingPunctuationAndYo() {
        #expect(FuzzyScore.tokenSort("Ёлка, ёлка!", "елка  елка") == 1)
        // The first text has the form the recognizer writes (`Benchmarks/cleanup/README.md`,
        // "The form of a raw transcript": a spoken time as `14.30`, an English term title-cased),
        // the second the phrase spoken. The word tokenizer keeps an inner decimal point inside a
        // word; folding has to turn it into a space first.
        #expect(FuzzyScore.tokenSort(
            "Созвон по Sprint Planning во вторник в 14.30.", "Созвон по sprint planning во вторник в 14:30."
        ) == 1)
        #expect(FuzzyScore.tokenSort("a", "b") == 0)
    }

    /// Stated sensitivity: scoring only the first reference gives an output in the other
    /// script of an English term below 1 (a Cyrillic and a Latin rendering are different
    /// letters); a mean over the references gives less than 1 for either form; a worst
    /// score does the same. The sample is `commands-editor-commit-push-03` of
    /// `Benchmarks/cleanup/slovo-cleanup-v1.json`.
    @Test
    func outputInAnyReferencesFormScoresOne() {
        let references = ["Сделай коммит и пуш в мейн.", "Сделай commit и push в main."]

        #expect(FuzzyScore.best("Сделай коммит и пуш в мейн.", references) == 1)
        #expect(FuzzyScore.best("Сделай commit и push в main.", references) == 1)
        #expect(FuzzyScore.best("Сделай commit и push в main.", [references[0]]) < 1)
        #expect(FuzzyScore.best("Сделай что-то другое.", references) < 1)
    }

    /// Stated sensitivity: splitting only on spaces leaves Chinese, Japanese and Thai
    /// as one word each. The exact segmentation is Apple's, so the test pins only
    /// that each text yields several words.
    @Test(arguments: ["今天天气很好我们去公园", "今日は天気がいいので公園に行きます", "วันนี้อากาศดีเราไปสวนสาธารณะกัน"])
    func unspacedScriptsSplitIntoWords(_ text: String) {
        #expect(FuzzyScore.words(text).count > 1)
    }

    /// Stated sensitivity: folding that keeps only decimal digits turns `5²` into `5`
    /// and `Ⅳ` into a space, so these pairs would compare equal.
    @Test
    func superscriptsAndRomanNumeralsAreKept() {
        #expect(FuzzyScore.tokenSort("5² и 5", "5 и 5") < 1)
        #expect(FuzzyScore.tokenSort("глава Ⅳ", "глава") < 1)
    }
}
