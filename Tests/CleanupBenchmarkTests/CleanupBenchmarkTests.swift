import Foundation
import Synchronization
import Testing

import CleanupBenchmark
import SlovoCore

@Suite("Cleanup benchmark harness")
struct CleanupBenchmarkTests {
    /// The raws are samples `code-switching-git-pr-01` and `code-switching-swift-tools-03` of
    /// `Benchmarks/cleanup/slovo-cleanup-v1.json`.
    ///
    /// Stated sensitivity: a runner that times only one provider, skips samples, or compares
    /// providers in candidate-major batches will miss the recorded interleaved call matrix.
    /// A runner that reuses the first candidate's output for every candidate → RED on the
    /// output assertion.
    @Test
    func runnerInvokesEveryCandidateForEverySampleAndRecordsTiming() async {
        let samples = [
            CleanupBenchmarkSample(id: "one", raw: "Ну вот запушь PR в GitHub, пожалуйста.", references: ["Запушь PR в GitHub, пожалуйста."]),
            CleanupBenchmarkSample(id: "two", raw: "запусти swift test потом swiftlint analyze", references: ["Запусти swift test, потом swiftlint analyze."]),
        ]
        let first = RecordingCleaner(output: "Запушь PR в GitHub, пожалуйста.")
        let second = RecordingCleaner(output: "Запусти swift test, потом swiftlint analyze.")
        let durations = Mutex<[UInt64]>([10, 20, 30, 40])
        let timer = CleanupBenchmarkTimer { operation in
            let output = try await operation()
            let duration = durations.withLock { $0.removeFirst() }
            return TimedCleanupOutput(output: output.text, durationNanoseconds: duration)
        }

        let report = await CleanupBenchmarkRunner(timer: timer).run(
            candidates: [
                CleanupBenchmarkCandidate(provider: "fake-a", model: "a", cleaner: first),
                CleanupBenchmarkCandidate(provider: "fake-b", model: "b", cleaner: second),
            ],
            samples: samples,
            config: CleanupConfig(model: "unused", writingStyle: .casual)
        )

        #expect(report.runs.map(\.durationNanoseconds) == [10, 20, 30, 40])
        #expect(report.runs.map(\.sampleId) == ["one", "one", "two", "two"])
        #expect(report.runs.map(\.candidateName) == ["fake-a:a", "fake-b:b", "fake-a:a", "fake-b:b"])
        #expect(report.runs.map(\.output) == [
            "Запушь PR в GitHub, пожалуйста.",
            "Запусти swift test, потом swiftlint analyze.",
            "Запушь PR в GitHub, пожалуйста.",
            "Запусти swift test, потом swiftlint analyze.",
        ])
        #expect(await first.rawInputs() == ["Ну вот запушь PR в GitHub, пожалуйста.", "запусти swift test потом swiftlint analyze"])
        #expect(await second.rawInputs() == ["Ну вот запушь PR в GitHub, пожалуйста.", "запусти swift test потом swiftlint analyze"])
        #expect(await first.modelInputs() == ["a", "a"])
        #expect(await second.modelInputs() == ["b", "b"])
    }

    /// The raw is sample `russian-filler-clean-desktop-02` of
    /// `Benchmarks/cleanup/slovo-cleanup-v1.json`.
    ///
    /// Stated sensitivity: an option whose value is the next flag takes the flag as its
    /// value, so `--outputs-file --failure-breakdown` names a file `--failure-breakdown`
    /// and the flag is lost after paid runs; each value-taking option must refuse a flag,
    /// `-h` included, as a missing value → RED.
    @Test(arguments: ["--outputs-file", "--write-baseline", "--providers", "--samples"], ["--failure-breakdown", "-h"])
    func optionValueThatIsAFlagIsMissing(option: String, flag: String) {
        #expect(throws: CleanupBenchmarkCommandError.missingValue(option)) {
            try CleanupBenchmarkCommandOptions.parse([option, flag][...])
        }
    }

    /// Stated sensitivity: counting warmup calls in the report, or measuring
    /// cold local-model loading as a timed run, makes the benchmark look worse
    /// than hot in-app cleanup behavior.
    @Test
    func runnerWarmsCandidatesBeforeRecordedRuns() async {
        let sample = CleanupBenchmarkSample(
            id: "warm", raw: "Короче, надо прибрать мусор на рабочем столе.", references: ["Надо прибрать мусор на рабочем столе."]
        )
        let cleaner = RecordingCleaner(output: "Надо прибрать мусор на рабочем столе.")
        let durations = Mutex<[UInt64]>([42])
        let timer = CleanupBenchmarkTimer { operation in
            let output = try await operation()
            let duration = durations.withLock { $0.removeFirst() }
            return TimedCleanupOutput(output: output.text, durationNanoseconds: duration)
        }

        let report = await CleanupBenchmarkRunner(timer: timer).run(
            candidates: [
                CleanupBenchmarkCandidate(provider: "fake", model: "hot", cleaner: cleaner),
            ],
            samples: [sample],
            config: CleanupConfig(model: "unused", writingStyle: .casual),
            repetitions: 1,
            warmupRepetitions: 2
        )

        #expect(report.runs.map(\.durationNanoseconds) == [42])
        #expect(report.runs.map(\.sampleId) == ["warm"])
        #expect(await cleaner.rawInputs() == Array(repeating: "Короче, надо прибрать мусор на рабочем столе.", count: 3))
        #expect(await cleaner.modelInputs() == ["hot", "hot", "hot"])
        let timerDurationsConsumed = durations.withLock { $0.isEmpty }
        #expect(timerDurationsConsumed)
    }

    /// Stated sensitivity: a translation sample must reach the cleaner as the app's translate hold,
    /// in the warmup call and in the measured one; a runner that builds the config without the
    /// flag or the target in either path, keeps one config for the whole candidate, or sets the
    /// flag on a plain sample → RED. The run carries the sample's `language`; a runner that
    /// drops it from the successful run → RED.
    @Test
    func translationSampleIsCleanedAsATranslateHoldAndAPlainOneIsNot() async {
        let samples = [
            CleanupBenchmarkSample(id: "plain", raw: "Привет.", references: ["Привет."]),
            CleanupBenchmarkSample(
                id: "translated", category: .translation, raw: "Привет.", references: ["Hello."], language: "ru", translationTarget: .init(code: "de")
            ),
        ]
        let seen = Mutex<[String]>([])
        let candidate = CleanupBenchmarkCandidate(provider: "fake", model: "m") { raw, config, _, _ in
            seen.withLock { $0.append("\(config.translate):\(config.translationTargetLanguage)") }
            return CleanupBenchmarkCleaned(text: raw)
        }

        let report = await CleanupBenchmarkRunner().run(
            candidates: [candidate],
            samples: samples,
            config: CleanupConfig(model: "unused", writingStyle: .casual),
            warmupRepetitions: 1
        )

        // The plain sample keeps the config's default target, which a plain pass never reads.
        #expect(seen.withLock { $0 } == ["false:en", "true:de", "false:en", "true:de"])
        #expect(report.runs.map(\.sampleLanguage) == [nil, "ru"])
    }

    /// Stated sensitivity: a sample's vocabulary and hints must reach the candidate as the sample
    /// wrote them, in the warmup call and in the measured one, and a sample with neither must reach
    /// it with an empty vocabulary and empty hints; a runner that passes one shared empty
    /// `PersonalizationContext` or `CleanupHints()` for every sample, in either path, or lends one
    /// sample's values to the next → RED.
    @Test
    func sampleVocabularyAndHintsReachTheCandidateAndAPlainSampleCarriesNone() async {
        let hints = CleanupHints(
            inputLocale: "en",
            spellFindings: [SpellFinding(token: "Zorp", guesses: ["Zorn"])],
            grammarFindings: [GrammarFinding(fragment: "me and him", message: "Check the pronouns.", corrections: ["he and I"])]
        )
        let samples = [
            CleanupBenchmarkSample(
                id: "carrying", category: .vocabulary, raw: "Zorp me and him.", references: ["x"],
                vocabulary: [.init(term: "QRV", expansion: "Quick Review"), .init(term: "Zorp")], hints: hints
            ),
            CleanupBenchmarkSample(id: "plain", raw: "Hello.", references: ["Hello."]),
        ]
        struct Seen: Equatable {
            let id: String
            let terms: [String]
            let hints: CleanupHints
        }
        let seen = Mutex<[Seen]>([])
        let candidate = CleanupBenchmarkCandidate(provider: "fake", model: "m") { raw, _, context, hints in
            let terms = context.vocabulary.map { "\($0.term)|\($0.expansion ?? "-")|\($0.lang)|\($0.weight)" }
            seen.withLock { $0.append(Seen(id: raw, terms: terms, hints: hints)) }
            return CleanupBenchmarkCleaned(text: raw)
        }

        _ = await CleanupBenchmarkRunner().run(
            candidates: [candidate],
            samples: samples,
            config: CleanupConfig(model: "unused", writingStyle: .casual),
            warmupRepetitions: 1
        )

        let carrying = Seen(
            id: "Zorp me and him.", terms: ["QRV|Quick Review|en|\(VocabularyQuickAdd.weight)", "Zorp|-|en|\(VocabularyQuickAdd.weight)"], hints: hints
        )
        let plain = Seen(id: "Hello.", terms: [], hints: CleanupHints())
        #expect(seen.withLock { $0 } == [carrying, plain, carrying, plain])
    }

    /// Stated sensitivity: a driver that calls `makeTransport` without `--judge` makes the CI
    /// smoke stage reach the network; the factory throws here, so that run exits 64 → RED.
    @Test
    func commandDriverWithoutJudgeSendsNothingAndIssuesNoVerdict() async throws {
        struct TransportMadeWithoutJudge: Error {}
        let driver = CleanupBenchmarkCommandDriver(makeTransport: { _ in throw TransportMadeWithoutJudge() })

        let result = await driver.run(arguments: ["--providers", "passthrough"], environment: [:])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("candidate,runs,failed_runs,p50_ms,p95_ms,max_ms,fuzzy,embedding,jev"))
        #expect(result.stdout.contains("passthrough:none,\(try CleanupBenchmarkDefaults.samples().count),0,"))
        #expect(!result.stdout.contains("verdict"))
        #expect(result.stderr.isEmpty)
    }

    /// Stated sensitivity: an exit code that ignores failed runs lets a provider
    /// error or an empty output pass a CI step.
    @Test
    func commandDriverExitsNonZeroWhenARunFailed() async {
        let driver = CleanupBenchmarkCommandDriver(runBenchmark: { plan in
            CleanupBenchmarkReport(runs: [
                CleanupBenchmarkRun(
                    sampleId: "hidden",
                    candidateName: plan.candidates[0].name,
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
        let driver = CleanupBenchmarkCommandDriver(runBenchmark: { plan in
            CleanupBenchmarkReport(runs: [
                CleanupBenchmarkRun(
                    sampleId: "hidden",
                    candidateName: plan.candidates[0].name,
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

    /// The sample is `russian-filler-check-01` of `Benchmarks/cleanup/slovo-cleanup-v1.json`.
    ///
    /// Stated sensitivity: trimming nothing before the emptiness check lets a
    /// whitespace-only answer through as an output; the fuzzy score of the empty
    /// text still comes out as 0.
    @Test
    func emptyOutputIsAFailureAndScoresZero() async {
        let sample = CleanupBenchmarkSample(
            id: "empty", raw: "Ну я сейчас проверяю, как работает диктовка.", references: ["Я сейчас проверяю, как работает диктовка."]
        )
        let report = await CleanupBenchmarkRunner().run(
            candidates: [CleanupBenchmarkCandidate(provider: "fake", model: "m", cleaner: RecordingCleaner(output: " \n "))],
            samples: [sample],
            config: CleanupConfig(model: "unused", writingStyle: .casual)
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
    /// provider error can persist payload text even when the formatter hides it. A failed run
    /// keeps the sample's `language` too, so its failure counts in its language row; a runner
    /// that drops it from the failed run → RED.
    @Test
    func runnerStoresCoarseErrorKindOnly() async {
        let sample = CleanupBenchmarkSample(
            id: "sensitive-sample", category: .languages, raw: "S3NT1NEL-RAW", references: ["Reference."], language: "uk"
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
            config: CleanupConfig(model: "unused", writingStyle: .casual)
        )

        #expect(report.runs.map(\.errorKind) == [.providerError])
        #expect(report.runs.map(\.failures) == [["provider-error"]])
        #expect(report.runs.map(\.sampleId) == ["sensitive-sample"])
        #expect(report.runs.map(\.sampleLanguage) == ["uk"])
        #expect(!String(describing: report.runs).contains("S3NT1NEL"))
        let rendered = CleanupBenchmarkReportFormatter.render(report)
        #expect(!rendered.contains("S3NT1NEL"))
    }
}
