import Foundation
import Testing

import CleanupBenchmark
import SlovoCore

@Suite("Cleanup benchmark dataset")
struct CleanupBenchmarkDatasetTests {
    /// Stated sensitivity: if the default benchmark silently falls back to an older
    /// sample set, or a sample loses its reference, this count and taxonomy check
    /// goes RED. A duplicated id would merge two samples' baseline slack.
    @Test
    func defaultDatasetLoadsPinnedSampleSuite() throws {
        let samples = try CleanupBenchmarkDefaults.samples()

        #expect(samples.count == 55)
        #expect(Self.countsByCategory(samples) == [
            .shortSmoke: 5,
            .russianFiller: 6,
            .codeSwitching: 10,
            .punctuationStructure: 12,
            .commandsEditor: 4,
            .inverseTextNormalization: 7,
            .safetyNegative: 8,
            .instructionShaped: 3,
        ])
        #expect(Set(samples.map(\.id)).count == samples.count)
        #expect(samples.allSatisfy { !$0.raw.isEmpty })
        #expect(samples.allSatisfy { !$0.reference.isEmpty })
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
            #"[{"id": "a", "raw": "\#(raw)", "reference": "\#(reference)", "expectation": {"maxLengthRatio": 1.8}}]"#.utf8
        )
        #expect(try CleanupBenchmarkSampleLoader.decode(oldFormat) == [
            CleanupBenchmarkSample(id: "a", raw: raw, reference: reference),
        ])
    }

    /// Stated sensitivity: settings with no repeats or no questions leave every output
    /// unscored with no error; dropping either guard lets one of these decode, so they
    /// are no longer refused before any paid call.
    @Test(arguments: [
        (repeats: 0, questions: #"{"q": {"type": "noul", "instructions": "?"}}"#),
        (repeats: 3, questions: "{}"),
    ])
    func judgeSettingsNeedAtLeastOneRepeatAndOneQuestion(repeats: Int, questions: String) {
        let json = """
        {"jev": {"model": "m", "path": "/p", "repeats": \(repeats), "questions": \(questions)},
         "embedding": {"model": "e", "path": "/e", "prefix": "", "provider": {"order": [], "allow_fallbacks": false}},
         "bar": {"floors": {"jev": 0.1, "embedding": 0.1, "fuzzy": 0.1}, "allowance": 0.05}}
        """
        #expect(throws: CleanupBenchmarkCommandError.invalidJudgeSettings) {
            try CleanupBenchmarkJudgeSettings.decode(Data(json.utf8))
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

        #expect(rendered.contains("candidate,category,runs,failed_runs,p50_ms,p95_ms,fuzzy,embedding,jev"))
        #expect(rendered.contains("openai:gpt-test,code-switching,1,0,1.0,1.0,0.500,0.250,0.750"))
        #expect(rendered.contains("openai:gpt-test,russian-filler,1,1,2.0,2.0,,,"))
        #expect(!rendered.contains("one"))
        #expect(!rendered.contains("two"))
    }

    private static func countsByCategory(_ samples: [CleanupBenchmarkSample]) -> [CleanupBenchmarkCategory: Int] {
        var counts: [CleanupBenchmarkCategory: Int] = [:]
        for sample in samples {
            counts[sample.category, default: 0] += 1
        }
        return counts
    }
}
