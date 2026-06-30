import Testing

import CleanupBenchmark
import SlovoCore

@Suite("Cleanup benchmark dataset")
struct CleanupBenchmarkDatasetTests {
    /// Stated sensitivity: if the default benchmark silently falls back to the
    /// old tiny inline sample set, this count and taxonomy check goes RED.
    @Test
    func defaultDatasetLoadsPinnedThirtySampleSuite() throws {
        let samples = try CleanupBenchmarkDefaults.samples()

        #expect(samples.count == 30)
        #expect(Self.countsByCategory(samples) == [
            .shortSmoke: 4,
            .russianFiller: 5,
            .codeSwitching: 6,
            .punctuationStructure: 5,
            .commandsEditor: 3,
            .inverseTextNormalization: 4,
            .safetyNegative: 3,
        ])
        #expect(samples.allSatisfy { !$0.raw.isEmpty })
        #expect(samples.allSatisfy { !($0.reference ?? "").isEmpty })
    }

    /// Stated sensitivity: matching forbidden Russian fillers by plain substring
    /// makes "ну" fail inside legitimate words such as "нужно".
    @Test
    func qualityGateChecksForbiddenTermsOnTokenBoundaries() {
        let sample = CleanupBenchmarkSample(
            id: "boundary",
            category: .russianFiller,
            raw: "ну нужно проверить cleanup",
            reference: "Нужно проверить cleanup.",
            expectation: CleanupQualityExpectation(
                requiredSubstrings: ["Нужно", "cleanup"],
                forbiddenTerms: ["ну"]
            )
        )

        let legitimate = CleanupQualityGate.evaluate(output: "Нужно проверить cleanup.", sample: sample)
        #expect(legitimate.passed)

        let filler = CleanupQualityGate.evaluate(output: "Ну, нужно проверить cleanup.", sample: sample)
        #expect(!filler.passed)
        #expect(filler.failures.contains("forbidden-term:ну"))
    }

    /// Stated sensitivity: if a cleaner keeps long dictated streams as a single
    /// clause with commas only, sentence-count checks may still miss it.
    @Test
    func qualityGateCanLimitRunOnWords() {
        let sample = CleanupBenchmarkSample(
            id: "run-on-limit",
            category: .punctuationStructure,
            raw: "первое проверь cleanup потом запусти тесты потом открой pull request",
            reference: "Первое: проверь cleanup. Потом запусти тесты. Потом открой pull request.",
            expectation: CleanupQualityExpectation(
                requiredSubstrings: ["cleanup", "pull request"],
                minimumSentenceTerminators: 2,
                maxRunOnWords: 6
            )
        )

        let runOn = CleanupQualityGate.evaluate(
            output: "Первое проверь cleanup, потом запусти тесты, потом открой pull request.",
            sample: sample
        )
        #expect(!runOn.passed)
        #expect(runOn.failures.contains("run-on-words"))

        let structured = CleanupQualityGate.evaluate(
            output: "Первое: проверь cleanup. Потом запусти тесты. Потом открой pull request.",
            sample: sample
        )
        #expect(structured.passed)
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
                quality: CleanupQualityResult(passed: true, failures: []),
                errorKind: nil
            ),
            CleanupBenchmarkRun(
                sampleId: "two",
                sampleCategory: .russianFiller,
                candidateName: "openai:gpt-test",
                durationNanoseconds: 2_000_000,
                quality: CleanupQualityResult(passed: false, failures: ["forbidden-term:ну"]),
                errorKind: nil
            ),
        ])

        let rendered = CleanupBenchmarkReportFormatter.renderCategoryBreakdown(report)

        #expect(rendered.contains("candidate,category,runs,passed,errors,p50_ms,p95_ms"))
        #expect(rendered.contains("openai:gpt-test,code-switching,1,1,0,1.0,1.0"))
        #expect(rendered.contains("openai:gpt-test,russian-filler,1,0,0,2.0,2.0"))
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
