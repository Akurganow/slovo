import Foundation
import Synchronization
import Testing

import CleanupBenchmark
import SlovoCore

@Suite("Cleanup benchmark harness")
struct CleanupBenchmarkTests {
    /// Stated sensitivity: a pass-through cleaner must not pass quality just
    /// because it is fast; the gate must catch filler words, missing casing, and
    /// missing punctuation without comparing the full answer byte-for-byte.
    @Test
    func qualityGateRejectsPassThroughAndChatResponses() {
        let sample = CleanupBenchmarkSample(
            id: "mixed-ru-en-fillers",
            raw: "ну вот запушь pr в github пожалуйста",
            expectation: CleanupQualityExpectation(
                requiredSubstrings: ["PR", "GitHub"],
                forbiddenSubstrings: ["ну", "вот"]
            )
        )

        let passThrough = CleanupQualityGate.evaluate(output: sample.raw, sample: sample)
        #expect(!passThrough.passed)
        #expect(passThrough.failures.contains("forbidden-substring:ну"))
        #expect(passThrough.failures.contains("required-substring:PR"))
        #expect(passThrough.failures.contains("terminal-punctuation"))

        let chatResponse = CleanupQualityGate.evaluate(
            output: "I'm not sure what you would like me to do with this transcript.",
            sample: sample
        )
        #expect(!chatResponse.passed)
        #expect(chatResponse.failures.contains("chat-response"))

        let wrapped = CleanupQualityGate.evaluate(
            output: "Sure: Запушь PR в GitHub, пожалуйста.",
            sample: sample
        )
        #expect(!wrapped.passed)
        #expect(wrapped.failures.contains("chat-response"))

        let cleaned = CleanupQualityGate.evaluate(
            output: "Запушь PR в GitHub, пожалуйста.",
            sample: sample
        )
        #expect(cleaned.passed)
    }

    /// Stated sensitivity: a cleanup output that keeps a long dictated stream as
    /// one run-on sentence must fail even when it preserves terms and punctuation.
    @Test
    func qualityGateCanRequireSentenceStructure() {
        let sample = CleanupBenchmarkSample(
            id: "run-on",
            raw: "сначала проверь cleanup потом запусти тесты потом открой pull request",
            expectation: CleanupQualityExpectation(
                requiredSubstrings: ["cleanup", "pull request"],
                minimumSentenceTerminators: 2
            )
        )

        let runOn = CleanupQualityGate.evaluate(
            output: "Сначала проверь cleanup, потом запусти тесты, потом открой pull request.",
            sample: sample
        )
        #expect(!runOn.passed)
        #expect(runOn.failures.contains("sentence-structure"))

        let structured = CleanupQualityGate.evaluate(
            output: "Сначала проверь cleanup. Потом запусти тесты. Потом открой pull request.",
            sample: sample
        )
        #expect(structured.passed)
    }

    /// Stated sensitivity: a runner that times only one provider, reuses one
    /// provider output for all candidates, skips samples, or compares providers
    /// in candidate-major batches will miss the recorded interleaved call matrix.
    @Test
    func runnerInvokesEveryCandidateForEverySampleAndRecordsTiming() async {
        let samples = [
            CleanupBenchmarkSample(
                id: "one",
                raw: "ну проверь pr",
                expectation: CleanupQualityExpectation(requiredSubstrings: ["PR"], forbiddenSubstrings: ["ну"])
            ),
            CleanupBenchmarkSample(
                id: "two",
                raw: "вот github работает",
                expectation: CleanupQualityExpectation(requiredSubstrings: ["GitHub"], forbiddenSubstrings: ["вот"])
            ),
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
            config: CleanupConfig(model: "unused", writingStyle: .casual, language: .auto),
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
        let sample = CleanupBenchmarkSample(
            id: "warm",
            raw: "ну проверь latency",
            expectation: CleanupQualityExpectation(requiredSubstrings: ["Latency"])
        )
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
            config: CleanupConfig(model: "unused", writingStyle: .casual, language: .auto),
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

    /// Stated sensitivity: breaking the CLI exit decision or bypassing argument
    /// parsing leaves the executable path green while the library pieces pass.
    @Test
    func commandDriverRunsCliPathAndReturnsQualityFailureExit() async {
        let result = await CleanupBenchmarkCommandDriver().run(
            arguments: ["--providers", "passthrough"],
            environment: [:]
        )

        #expect(result.exitCode == 2)
        #expect(result.stdout.contains("passthrough:none"))
        #expect(result.stderr.isEmpty)
    }

    /// Stated sensitivity: a thin executable wrapper can silently bypass the
    /// testable command driver unless the production entrypoint is guarded too.
    @Test
    func executableEntrypointDelegatesToCommandDriver() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appending(path: "Tools/cleanup-benchmark-cli/main.swift"),
            encoding: .utf8
        )

        #expect(source.contains("import CleanupBenchmark"))
        #expect(!source.contains("import SlovoCore"))
        #expect(source.contains("CleanupBenchmarkCommandDriver().run("))
        #expect(source.contains("Array(CommandLine.arguments.dropFirst())"))
        #expect(source.contains("ProcessInfo.processInfo.environment"))
        #expect(source.contains("print(result.stdout)"))
        #expect(source.contains("fputs(result.stderr, stderr)"))
        #expect(source.contains("Foundation.exit(result.exitCode)"))
    }

    /// Stated sensitivity: source-shape checks alone can leave a broken
    /// executable green if the real entrypoint exits before running the driver;
    /// running SwiftPM recursively inside `swift test` can also deadlock on the
    /// build lock, so the executable smoke belongs in diagnose instead.
    @Test
    func executableEntrypointRunsBenchmarkCommand() throws {
        let diagnose = try String(
            contentsOf: repositoryRoot().appending(path: "Scripts/diagnose.sh"),
            encoding: .utf8
        )
        let smoke = try String(
            contentsOf: repositoryRoot().appending(path: "Scripts/check-cleanup-benchmark-cli.sh"),
            encoding: .utf8
        )

        #expect(diagnose.contains(#"run_stage "cleanup-benchmark-cli" Scripts/check-cleanup-benchmark-cli.sh"#))
        #expect(smoke.contains("swift run --disable-automatic-resolution slovo-cleanup-benchmark"))
        #expect(smoke.contains("--providers passthrough"))
        #expect(smoke.contains("--samples"))
        #expect(smoke.contains("--repetitions 1"))
        #expect(!smoke.contains("--scratch-path"))
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
                    quality: CleanupQualityResult(passed: true, failures: []),
                    errorKind: nil
                ),
            ])
        })

        let result = await driver.run(arguments: ["--providers", "passthrough"], environment: [:])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("passthrough:none"))
        #expect(result.stderr.isEmpty)
    }

    /// Stated sensitivity: raw transcripts, cleaned text, sample ids, and raw
    /// provider errors must not reach the rendered benchmark report.
    @Test
    func reportFormatterShowsMetricsWithoutPayloadText() {
        let report = CleanupBenchmarkReport(runs: [
            CleanupBenchmarkRun(
                sampleId: "sample-secret",
                candidateName: "openai:gpt-test",
                durationNanoseconds: 12_000_000,
                quality: CleanupQualityResult(passed: true, failures: []),
                errorKind: nil
            ),
        ])

        let rendered = CleanupBenchmarkReportFormatter.render(report)

        #expect(rendered.contains("openai:gpt-test"))
        #expect(rendered.contains("p50_ms"))
        #expect(!rendered.contains("raw"))
        #expect(!rendered.contains("cleaned"))
        #expect(!rendered.contains("sample-secret"))
    }

    /// Stated sensitivity: if the runner stores `String(describing: error)`, a
    /// provider error can persist payload text even when the formatter hides it.
    @Test
    func runnerStoresCoarseErrorKindOnly() async {
        let sample = CleanupBenchmarkSample(
            id: "sensitive-sample",
            raw: "S3NT1NEL-RAW",
            expectation: CleanupQualityExpectation()
        )
        let report = await CleanupBenchmarkRunner().run(
            candidates: [
                CleanupBenchmarkCandidate(
                    provider: "fake",
                    model: "throwing",
                    cleaner: ThrowingSensitiveCleaner()
                ),
            ],
            samples: [sample],
            config: CleanupConfig(model: "unused", writingStyle: .casual, language: .auto),
            context: PersonalizationContext(vocabulary: [])
        )

        #expect(report.runs.map(\.errorKind) == [.providerError])
        #expect(report.runs.map(\.quality.failures) == [["provider-error"]])
        #expect(report.runs.map(\.sampleId) == ["sensitive-sample"])
        #expect(!String(describing: report.runs).contains("S3NT1NEL"))
        let rendered = CleanupBenchmarkReportFormatter.render(report)
        #expect(!rendered.contains("S3NT1NEL"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
