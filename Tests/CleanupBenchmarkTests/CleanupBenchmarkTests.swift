import Foundation
import Synchronization
import Testing

import CleanupBenchmark
import SlovoCore

@Suite("Cleanup benchmark harness")
struct CleanupBenchmarkTests {
    /// Stated sensitivity: a runner that times only one provider, reuses one
    /// provider output for all candidates, skips samples, or compares providers
    /// in candidate-major batches will miss the recorded interleaved call matrix.
    @Test
    func runnerInvokesEveryCandidateForEverySampleAndRecordsTiming() async {
        let samples = [
            CleanupBenchmarkSample(id: "one", raw: "ну проверь pr", reference: "Проверь PR."),
            CleanupBenchmarkSample(id: "two", raw: "вот github работает", reference: "GitHub работает."),
        ]
        let first = RecordingCleaner(output: "Проверь PR.")
        let second = RecordingCleaner(output: "GitHub работает.")
        let durations = Mutex<[UInt64]>([10, 20, 30, 40])
        let timer = CleanupBenchmarkTimer { operation in
            let output = try await operation()
            let duration = durations.withLock { $0.removeFirst() }
            return TimedCleanupOutput(output: output, durationNanoseconds: duration)
        }

        let report = await CleanupBenchmarkRunner(timer: timer).run(
            candidates: [
                CleanupBenchmarkCandidate(provider: "fake-a", model: "a", cleaner: first),
                CleanupBenchmarkCandidate(provider: "fake-b", model: "b", cleaner: second),
            ],
            samples: samples,
            config: CleanupConfig(model: "unused", writingStyle: .casual),
            context: PersonalizationContext(vocabulary: [])
        )

        #expect(report.runs.map(\.durationNanoseconds) == [10, 20, 30, 40])
        #expect(report.runs.map(\.sampleId) == ["one", "one", "two", "two"])
        #expect(report.runs.map(\.candidateName) == ["fake-a:a", "fake-b:b", "fake-a:a", "fake-b:b"])
        #expect(await first.rawInputs() == ["ну проверь pr", "вот github работает"])
        #expect(await second.rawInputs() == ["ну проверь pr", "вот github работает"])
        #expect(await first.modelInputs() == ["a", "a"])
        #expect(await second.modelInputs() == ["b", "b"])
    }

    /// Stated sensitivity: counting warmup calls in the report, or measuring
    /// cold local-model loading as a timed run, makes the benchmark look worse
    /// than hot in-app cleanup behavior.
    @Test
    func runnerWarmsCandidatesBeforeRecordedRuns() async {
        let sample = CleanupBenchmarkSample(id: "warm", raw: "ну проверь latency", reference: "Проверь latency.")
        let cleaner = RecordingCleaner(output: "Проверь latency.")
        let durations = Mutex<[UInt64]>([42])
        let timer = CleanupBenchmarkTimer { operation in
            let output = try await operation()
            let duration = durations.withLock { $0.removeFirst() }
            return TimedCleanupOutput(output: output, durationNanoseconds: duration)
        }

        let report = await CleanupBenchmarkRunner(timer: timer).run(
            candidates: [
                CleanupBenchmarkCandidate(provider: "fake", model: "hot", cleaner: cleaner),
            ],
            samples: [sample],
            config: CleanupConfig(model: "unused", writingStyle: .casual),
            context: PersonalizationContext(vocabulary: []),
            repetitions: 1,
            warmupRepetitions: 2
        )

        #expect(report.runs.map(\.durationNanoseconds) == [42])
        #expect(report.runs.map(\.sampleId) == ["warm"])
        #expect(await cleaner.rawInputs() == ["ну проверь latency", "ну проверь latency", "ну проверь latency"])
        #expect(await cleaner.modelInputs() == ["hot", "hot", "hot"])
        let timerDurationsConsumed = durations.withLock { $0.isEmpty }
        #expect(timerDurationsConsumed)
    }

    /// Stated sensitivity: a driver that builds the judge or sends a request without
    /// `--judge` makes the CI smoke stage call the network, and fails this test.
    @Test
    func commandDriverWithoutJudgeSendsNothingAndIssuesNoVerdict() async throws {
        let transport = FakeJudgeTransport()
        let driver = CleanupBenchmarkCommandDriver(makeTransport: { _ in transport })

        let result = await driver.run(arguments: ["--providers", "passthrough"], environment: [:])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("candidate,runs,failed_runs,p50_ms,p95_ms,fuzzy,embedding,jev"))
        #expect(result.stdout.contains("passthrough:none,55,0,"))
        #expect(!result.stdout.contains("verdict"))
        #expect(result.stderr.isEmpty)
        #expect(transport.recorded().isEmpty)
    }

    /// Stated sensitivity: an exit code that ignores failed runs lets a provider
    /// error or an empty output pass a CI step.
    @Test
    func commandDriverExitsNonZeroWhenARunFailed() async {
        let driver = CleanupBenchmarkCommandDriver(runBenchmark: { candidates, _, _, _, _, _ in
            CleanupBenchmarkReport(runs: [
                CleanupBenchmarkRun(
                    sampleId: "hidden",
                    candidateName: candidates[0].name,
                    durationNanoseconds: 0,
                    failures: ["provider-error"],
                    errorKind: .providerError
                ),
            ])
        })

        let result = await driver.run(arguments: ["--providers", "passthrough"], environment: [:])

        #expect(result.exitCode == 2)
        #expect(result.stderr.isEmpty)
    }

    /// Stated sensitivity: changing the command driver to exit non-zero even
    /// when every run passes is not caught by lower-level runner tests.
    @Test
    func commandDriverReturnsSuccessWhenEveryRunPasses() async {
        let driver = CleanupBenchmarkCommandDriver(runBenchmark: { candidates, _, _, _, _, _ in
            CleanupBenchmarkReport(runs: [
                CleanupBenchmarkRun(
                    sampleId: "hidden",
                    candidateName: candidates[0].name,
                    durationNanoseconds: 1_000_000,
                    errorKind: nil
                ),
            ])
        })

        let result = await driver.run(arguments: ["--providers", "passthrough"], environment: [:])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("passthrough:none"))
        #expect(result.stderr.isEmpty)
    }

    /// Stated sensitivity: trimming nothing before the emptiness check lets a
    /// whitespace-only answer through as an output; the fuzzy score of the empty
    /// text still comes out as 0.
    @Test
    func emptyOutputIsAFailureAndScoresZero() async {
        let sample = CleanupBenchmarkSample(id: "empty", raw: "ну привет", reference: "Привет.")
        let report = await CleanupBenchmarkRunner().run(
            candidates: [CleanupBenchmarkCandidate(provider: "fake", model: "m", cleaner: RecordingCleaner(output: " \n "))],
            samples: [sample],
            config: CleanupConfig(model: "unused", writingStyle: .casual),
            context: PersonalizationContext(vocabulary: [])
        )

        #expect(report.runs.map(\.failures) == [["empty-output"]])
        #expect(report.runs.map(\.scores.fuzzy) == [0])
    }

    /// The rendered report shows metrics only, never the run's sample id.
    /// (End-to-end raw/cleaned redaction is covered by `runnerStoresCoarseErrorKindOnly`.)
    @Test
    func reportFormatterShowsMetricsWithoutPayloadText() {
        let report = CleanupBenchmarkReport(runs: [
            CleanupBenchmarkRun(
                sampleId: "sample-secret",
                candidateName: "openai:gpt-test",
                durationNanoseconds: 12_000_000,
                output: "OUTPUT-SECRET",
                errorKind: nil
            ),
        ])

        let rendered = CleanupBenchmarkReportFormatter.render(report)

        #expect(rendered.contains("openai:gpt-test"))
        #expect(rendered.contains("p50_ms"))
        #expect(!rendered.contains("sample-secret"))
        #expect(!rendered.contains("OUTPUT-SECRET"))
    }

    /// Stated sensitivity: if the runner stores `String(describing: error)`, a
    /// provider error can persist payload text even when the formatter hides it.
    @Test
    func runnerStoresCoarseErrorKindOnly() async {
        let sample = CleanupBenchmarkSample(id: "sensitive-sample", raw: "S3NT1NEL-RAW", reference: "Reference.")
        let report = await CleanupBenchmarkRunner().run(
            candidates: [
                CleanupBenchmarkCandidate(
                    provider: "fake",
                    model: "throwing",
                    cleaner: ThrowingSensitiveCleaner()
                ),
            ],
            samples: [sample],
            config: CleanupConfig(model: "unused", writingStyle: .casual),
            context: PersonalizationContext(vocabulary: [])
        )

        #expect(report.runs.map(\.errorKind) == [.providerError])
        #expect(report.runs.map(\.failures) == [["provider-error"]])
        #expect(report.runs.map(\.sampleId) == ["sensitive-sample"])
        #expect(!String(describing: report.runs).contains("S3NT1NEL"))
        let rendered = CleanupBenchmarkReportFormatter.render(report)
        #expect(!rendered.contains("S3NT1NEL"))
    }
}
