import Foundation
import Testing

import CleanupBenchmark
import SlovoCore

@Suite("Cleanup benchmark dataset")
struct CleanupBenchmarkDatasetTests {
    /// Stated sensitivity: if the default benchmark silently falls back to an older
    /// sample set, or a sample loses its reference, this count and taxonomy check
    /// goes RED. A duplicated id makes the loader throw, so it fails this test too.
    @Test
    func defaultDatasetLoadsPinnedSampleSuite() throws {
        let samples = try CleanupBenchmarkDefaults.samples()

        #expect(samples.count == 198)
        #expect(Self.countsByCategory(samples) == [
            .shortSmoke: 20,
            .russianFiller: 18,
            .codeSwitching: 13,
            .punctuationStructure: 18,
            .commandsEditor: 4,
            .inverseTextNormalization: 11,
            .safetyNegative: 8,
            .instructionShaped: 3,
            .languages: 40,
            .mixedLanguages: 15,
            .translation: 36,
            .vocabulary: 4,
            .hints: 8,
        ])
        #expect(samples.allSatisfy { !$0.raw.isEmpty })
        #expect(samples.allSatisfy { !$0.references.isEmpty })
    }

    /// Stated sensitivity: a set whose translations all go into another language, or all start
    /// in the target (en into en, ru into ru), would leave one of the two cases the prompt must
    /// handle unmeasured with no error; the loaded set must hold both → RED.
    @Test
    func defaultDatasetHoldsBothKindsOfTranslation() throws {
        let samples = try CleanupBenchmarkDefaults.samples()
        let translations = samples.filter { $0.category == .translation }
        #expect(translations.contains { $0.language == $0.translateTo })
        #expect(translations.contains { $0.language != $0.translateTo })
    }

    /// Stated sensitivity: a code the catalogue does not offer reaches the prompt as a bare
    /// string, and a key its category does not take is silently unused, so each case below
    /// must be refused when the file is read; dropping any one of the decoder's checks
    /// (catalogue code of `language` or of `translateTo`, translation if and only if
    /// `translateTo`, the number of codes a category takes, a third code in a translation
    /// source included, `language` outside the three categories) lets its case load → RED. The vocabulary
    /// and hints cases are refused for the same reason: a blank term, an empty hints object or list, or a
    /// spell token the raw (`x`) does not hold would reach the prompt as nothing or as a hint the
    /// checker could not give, and a `vocabulary` or `hints` sample without its own key would test
    /// nothing; dropping the blank-term check, the empty-hints checks, the spell-token check or either
    /// category rule lets its case load → RED. The cases marked accepted are the accepted shapes.
    @Test(arguments: [
        (#""category": "translation", "language": "ru", "translateTo": "xx""#, false),
        (#""category": "translation", "language": "xx", "translateTo": "en""#, false),
        (#""category": "mixed-languages", "language": "de+xx""#, false),
        (#""category": "translation", "language": "ru""#, false),
        (#""category": "short-smoke", "translateTo": "en""#, false),
        (#""category": "languages""#, false),
        (#""category": "languages", "language": "de+en""#, false),
        (#""category": "mixed-languages", "language": "de""#, false),
        (#""category": "short-smoke", "language": "de""#, false),
        (#""category": "languages", "language": "de", "translateTo": "en""#, false),
        (#""category": "translation", "language": "ru+en+de", "translateTo": "en""#, false),
        (#""category": "translation", "language": "ru+en", "translateTo": "en""#, true),
        (#""category": "translation", "translateTo": "en""#, true),
        (#""vocabulary": [{"term": "QRV"}, {"term": " \t"}]"#, false),
        (#""vocabulary": [{"term": ""}]"#, false),
        (#""hints": {}"#, false),
        (#""hints": {"spell": []}"#, false),
        (#""hints": {"grammar": []}"#, false),
        (#""hints": {"spell": [{"token": "y", "guesses": ["x"]}]}"#, false),
        (#""hints": {"spell": [{"token": "", "guesses": []}]}"#, false),
        (#""category": "vocabulary""#, false),
        (#""category": "vocabulary", "vocabulary": [], "hints": {"inputLocale": "en"}"#, false),
        (#""category": "hints", "vocabulary": [{"term": "QRV"}]"#, false),
        (#""category": "vocabulary", "vocabulary": [{"term": "QRV", "expansion": "Quick Review"}]"#, true),
        (#""category": "hints", "hints": {"inputLocale": "en"}"#, true),
        (#""category": "short-smoke", "vocabulary": [{"term": "QRV"}], "hints": {"spell": [{"token": "x", "guesses": []}]}"#, true),
        (#""category": "translation", "translateTo": "de", "vocabulary": [{"term": "QRV"}], "hints": {"grammar": [{"fragment": "x", "message": "m"}]}"#, true),
    ])
    func sampleKeysAgreeWithTheirCategory(keys: String, accepted: Bool) {
        let data = Data(#"[{"id": "a", "raw": "x", "references": ["x"], \#(keys)}]"#.utf8)
        if accepted {
            #expect((try? CleanupBenchmarkSampleLoader.decode(data)) != nil)
        } else {
            #expect(throws: DecodingError.self) {
                try CleanupBenchmarkSampleLoader.decode(data)
            }
        }
    }

    /// Stated sensitivity: the keys must reach the sample as the values written: a term keeps its
    /// expansion, an absent expansion stays nil, and every hint member lands in its own field of
    /// `CleanupHints`; a decoder that swaps `message` and `fragment`, drops the guesses, or loses
    /// the locale → RED. A sample with neither key has no vocabulary and the empty hints.
    @Test
    func vocabularyAndHintsDecodeIntoTheValuesWritten() throws {
        let data = Data(#"""
        [{"id": "a", "raw": "Kubrix me and him", "references": ["x"],
          "vocabulary": [{"term": "QRV", "expansion": "Quick Review"}, {"term": "Zorp"}],
          "hints": {"inputLocale": "en", "spell": [{"token": "Kubrix", "guesses": ["Kubrick", "Kubric"]}],
                    "grammar": [{"fragment": "me and him", "message": "Check the pronouns.", "corrections": ["he and I"]}]}},
         {"id": "b", "raw": "x", "references": ["x"]}]
        """#.utf8)
        let samples = try CleanupBenchmarkSampleLoader.decode(data)

        #expect(samples[0].vocabulary == [
            CleanupBenchmarkVocabularyEntry(term: "QRV", expansion: "Quick Review"),
            CleanupBenchmarkVocabularyEntry(term: "Zorp"),
        ])
        #expect(samples[0].hints == CleanupHints(
            inputLocale: "en",
            spellFindings: [SpellFinding(token: "Kubrix", guesses: ["Kubrick", "Kubric"])],
            grammarFindings: [GrammarFinding(fragment: "me and him", message: "Check the pronouns.", corrections: ["he and I"])]
        ))
        #expect(samples[1].vocabulary.isEmpty)
        #expect(samples[1].hints == CleanupHints())
    }

    /// The sample is `russian-filler-check-01` of `Benchmarks/cleanup/slovo-cleanup-v1.json`.
    ///
    /// Stated sensitivity: a sample file whose entry has no reference must not load:
    /// every output is scored against the reference, and a default would score
    /// against nothing. Keys the old format carried are ignored.
    @Test
    func sampleWithoutReferenceFailsToLoadAndOldKeysAreIgnored() throws {
        let raw = "Ну я сейчас проверяю, как работает диктовка."
        let reference = "Я сейчас проверяю, как работает диктовка."
        let withoutReference = Data(#"[{"id": "a", "raw": "\#(raw)"}]"#.utf8)
        #expect(throws: DecodingError.self) {
            try CleanupBenchmarkSampleLoader.decode(withoutReference)
        }

        let oldFormat = Data(
            #"[{"id": "a", "raw": "\#(raw)", "references": ["\#(reference)"], "expectation": {"maxLengthRatio": 1.8}}]"#.utf8
        )
        #expect(try CleanupBenchmarkSampleLoader.decode(oldFormat) == [
            CleanupBenchmarkSample(id: "a", raw: raw, references: [reference]),
        ])
    }

    /// Stated sensitivity: settings with no repeats, no questions or no translation questions (a
    /// translation sample would then be asked nothing), no repetition left after
    /// dropping the worst, or an allowance or a floor outside 0...1 leave every output
    /// unscored, every sample without a slack, a bar that never fails, or a trap in the miss
    /// count (an allowance of 1e20), with no error; dropping any guard lets one of these
    /// decode, so they are no longer refused before any paid call.
    @Test(arguments: [
        BadJudgeSettings(repeats: 0),
        BadJudgeSettings(questions: "{}"),
        BadJudgeSettings(translationQuestions: "{}"),
        BadJudgeSettings(repetitions: 2),
        BadJudgeSettings(dropWorst: -1),
        BadJudgeSettings(allowance: 5),
        BadJudgeSettings(allowance: 1e20),
        BadJudgeSettings(floor: 1.5),
        BadJudgeSettings(floor: -0.1),
    ])
    func judgeSettingsNeedAScoreAndASlack(settings: BadJudgeSettings) {
        let json = """
        {"jev": {"model": "m", "path": "/p", "repeats": \(settings.repeats), "questions": \(settings.questions),
                  "translationQuestions": \(settings.translationQuestions)},
         "embedding": {"model": "e", "path": "/e", "prefix": "", "provider": {"order": [], "allow_fallbacks": false}},
         "bar": {"floors": {"jev": \(settings.floor), "embedding": 0.1, "fuzzy": 0.1}, "allowance": \(settings.allowance),
                 "repetitions": \(settings.repetitions), "dropWorst": \(settings.dropWorst)}}
        """
        #expect(throws: CleanupBenchmarkCommandError.invalidJudgeSettings) {
            try CleanupBenchmarkJudgeSettings.decode(Data(json.utf8))
        }
    }

    /// Valid judge settings with one value changed to a bad one.
    struct BadJudgeSettings: Sendable {
        var repeats = 3
        var questions = #"{"q": {"type": "noul", "instructions": "?"}}"#
        var translationQuestions = #"{"q": {"type": "noul", "instructions": "?"}}"#
        var repetitions = 5
        var dropWorst = 2
        var allowance = 0.05
        var floor = 0.1
    }

    /// Stated sensitivity: a sample file with two samples of one id merges their runs, their
    /// references and their baseline slack (every consumer keys by id), so the paid runs
    /// are wrong without a trace; both file shapes must be refused, naming the id.
    @Test
    func duplicateSampleIdIsRefused() {
        let array = Data(#"[{"id": "a", "raw": "x", "references": ["x"]}, {"id": "a", "raw": "y", "references": ["y"]}]"#.utf8)
        let object = Data(#"{"samples": [{"id": "a", "raw": "x", "references": ["x"]}, {"id": "a", "raw": "y", "references": ["y"]}]}"#.utf8)

        for data in [array, object] {
            #expect(throws: CleanupBenchmarkCommandError.duplicateSampleId("a")) {
                try CleanupBenchmarkSampleLoader.decode(data)
            }
        }
    }

    /// Stated sensitivity: an empty sample list runs nothing and prints an empty report with
    /// exit 0, so a loader that accepts it lets a run pass with no sample measured; both file
    /// shapes must be refused → RED.
    @Test
    func emptySampleListIsRefused() {
        for data in [Data("[]".utf8), Data(#"{"samples": []}"#.utf8)] {
            #expect(throws: CleanupBenchmarkCommandError.noSamples) {
                try CleanupBenchmarkSampleLoader.decode(data)
            }
        }
    }

    /// Stated sensitivity: a committed baseline that does not decode fails every
    /// `--baseline` run; the committed file must parse as the file model.
    @Test
    func committedBaselineFileDecodes() throws {
        let path = URL(fileURLWithPath: CleanupBenchmarkJudgeSettings.defaultPath)
            .deletingLastPathComponent().appending(path: "baseline.json")
        _ = try CleanupBenchmarkBaselineFile.decode(Data(contentsOf: path))
    }

    /// Stated sensitivity: without per-category output, a provider can regress
    /// on one product slice while the aggregate still looks acceptable.
    @Test
    func reportFormatterShowsCategoryBreakdown() {
        let report = CleanupBenchmarkReport(runs: [
            CleanupBenchmarkRun(
                sampleId: "one",
                sampleCategory: .codeSwitching,
                candidateName: "openai:gpt-test",
                durationNanoseconds: 1_000_000,
                scores: CleanupBenchmarkScores(fuzzy: 0.5, embedding: 0.25, jev: 0.75),
                errorKind: nil
            ),
            CleanupBenchmarkRun(
                sampleId: "two",
                sampleCategory: .russianFiller,
                candidateName: "openai:gpt-test",
                durationNanoseconds: 2_000_000,
                failures: ["empty-output"],
                errorKind: nil
            ),
        ])

        let rendered = CleanupBenchmarkReportFormatter.renderCategoryBreakdown(report)

        #expect(rendered.contains("candidate,category,runs,failed_runs,p50_ms,p95_ms,max_ms,fuzzy,embedding,jev"))
        #expect(rendered.contains("openai:gpt-test,code-switching,1,0,1.0,1.0,1.0,0.500,0.250,0.750"))
        #expect(rendered.contains("openai:gpt-test,russian-filler,1,1,2.0,2.0,2.0,,,"))
        #expect(!rendered.contains("one"))
        #expect(!rendered.contains("two"))
    }

    /// Stated sensitivity: without a language row a language that fails hides under its
    /// category (the breakdown rows are what the verdict rows are read beside); the rows
    /// follow the categories, a `translation` sample's `language` makes none, and `max_ms`
    /// is the slowest successful run: a max over all runs would show the provider error's
    /// 999 ms, and a 95th percentile would show 20 where the slowest run took 80.
    @Test
    func breakdownAddsLanguageRowsAfterCategoriesAndShowsTheSlowestRun() {
        func run(_ id: String, _ category: CleanupBenchmarkCategory, _ language: String?, milliseconds: UInt64, failed: Bool = false)
            -> CleanupBenchmarkRun {
            CleanupBenchmarkRun(
                sampleId: id, sampleCategory: category, sampleLanguage: language, candidateName: "c",
                durationNanoseconds: milliseconds * 1_000_000, failures: failed ? ["provider-error"] : [],
                errorKind: failed ? .providerError : nil
            )
        }
        let report = CleanupBenchmarkReport(runs: [
            run("a", .languages, "uk", milliseconds: 5),
            run("b", .mixedLanguages, "de+en", milliseconds: 100),
            run("c", .translation, "de", milliseconds: 7),
        ] + (1...20).map { run("n\($0)", .shortSmoke, nil, milliseconds: UInt64($0)) }
            + [run("slow", .shortSmoke, nil, milliseconds: 80), run("e", .shortSmoke, nil, milliseconds: 999, failed: true)])

        let rows = CleanupBenchmarkReportFormatter.renderCategoryBreakdown(report).split(separator: "\n").map(String.init)

        #expect(rows.map { $0.split(separator: ",")[1] } == ["category", "languages", "mixed-languages", "short-smoke", "translation", "de+en", "uk"])
        #expect(rows[2].hasPrefix("c,mixed-languages,1,0,100.0,100.0,100.0,"))
        #expect(rows[3].hasPrefix("c,short-smoke,22,1,11.0,20.0,80.0,"))
        #expect(rows.last?.hasPrefix("c,uk,1,0,5.0,5.0,5.0,") == true)
    }

    private static func countsByCategory(_ samples: [CleanupBenchmarkSample]) -> [CleanupBenchmarkCategory: Int] {
        var counts: [CleanupBenchmarkCategory: Int] = [:]
        for sample in samples {
            counts[sample.category, default: 0] += 1
        }
        return counts
    }
}
