import Foundation
import Synchronization
import Testing

@testable import CleanupBenchmark
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
                CleanupBenchmarkCandidate(provider: "fake", model: "a", cleaner: first),
                CleanupBenchmarkCandidate(provider: "fake", model: "b", cleaner: second),
            ],
            samples: samples,
            config: CleanupConfig(model: "unused", writingStyle: .casual)
        )

        #expect(report.runs.map(\.durationNanoseconds) == [10, 20, 30, 40])
        #expect(report.runs.map(\.sampleId) == ["one", "one", "two", "two"])
        #expect(report.runs.map(\.candidateName) == ["fake:a", "fake:b", "fake:a", "fake:b"])
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

    /// Stated sensitivity: a lane that ignores its width starts every call at once and reaches more than
    /// 3 in flight on nearly every run (the calls are held across 20 yields) → RED; a runner that makes
    /// fewer than 3 calls at a time never opens the gate, which needs 3 in flight, so the time limit
    /// ends the test → RED. The gate opens on a count, never on time, so a runner that honours the
    /// width never waits on the clock.
    @Test(.timeLimit(.minutes(1)))
    func laneRunsUpToItsWidthOfCallsAtOnce() async {
        let samples = (1...5).map { CleanupBenchmarkSample(id: "s\($0)", raw: "Hello.", references: ["Hello."]) }
        let flight = FlightCounter()
        let gate = Gate()
        let candidate = CleanupBenchmarkCandidate(provider: "fake", model: "wide", lane: "wide", width: 3) { raw, _, _, _ in
            if flight.enter() == 3 {
                gate.open()
            }
            await gate.wait()
            await FlightCounter.hold()
            flight.leave()
            return CleanupBenchmarkCleaned(text: raw)
        }

        let report = await CleanupBenchmarkRunner().run(
            candidates: [candidate], samples: samples, config: CleanupConfig(model: "unused", writingStyle: .casual)
        )

        #expect(flight.peak == 3)
        #expect(report.runs.map(\.sampleId) == ["s1", "s2", "s3", "s4", "s5"])
    }

    /// Stated sensitivity: a lane key taken from the candidate name for a candidate made by hand
    /// lets two candidates of one provider overlap, so 2 are in flight → RED. The overlap is
    /// detected, not guaranteed: the calls are held across 20 yields, so a runner that overlaps them
    /// is caught on nearly every run, and a runner that keeps the lane never fails.
    @Test
    func candidatesOfOneProviderShareALaneOfOneCallAtATime() async {
        let samples = (1...3).map { CleanupBenchmarkSample(id: "s\($0)", raw: "Hello.", references: ["Hello."]) }
        let flight = FlightCounter()
        func candidate(_ model: String) -> CleanupBenchmarkCandidate {
            CleanupBenchmarkCandidate(provider: "fake", model: model) { raw, _, _, _ in
                _ = flight.enter()
                await FlightCounter.hold()
                flight.leave()
                return CleanupBenchmarkCleaned(text: raw)
            }
        }

        let report = await CleanupBenchmarkRunner().run(
            candidates: [candidate("a"), candidate("b")],
            samples: samples,
            config: CleanupConfig(model: "unused", writingStyle: .casual),
            repetitions: 2
        )

        #expect(flight.peak == 1)
        #expect(report.runs.count == 12)
    }

    /// Stated sensitivity: one lane for every candidate makes the first call of `fake:a` wait for a
    /// start of `fake:b` that cannot come before it ends, so the time limit ends the test → RED.
    /// The first call of `fake:b` opens the gate on its start, never on time.
    @Test(.timeLimit(.minutes(1)))
    func candidatesOfDistinctLanesRunAtOnce() async {
        let sample = CleanupBenchmarkSample(id: "s", raw: "Hello.", references: ["Hello."])
        let gate = Gate()
        let first = CleanupBenchmarkCandidate(provider: "fake", model: "a", lane: "x") { raw, _, _, _ in
            await gate.wait()
            return CleanupBenchmarkCleaned(text: raw)
        }
        let second = CleanupBenchmarkCandidate(provider: "fake", model: "b", lane: "y") { raw, _, _, _ in
            gate.open()
            return CleanupBenchmarkCleaned(text: raw)
        }

        let report = await CleanupBenchmarkRunner().run(
            candidates: [first, second], samples: [sample], config: CleanupConfig(model: "unused", writingStyle: .casual)
        )

        #expect(report.runs.map(\.candidateName) == ["fake:a", "fake:b"])
    }

    /// Stated sensitivity: a runner that records after its loop, in matrix order or in any order,
    /// never opens the gate that `record` opens for the call of sample `one`, so the time limit ends
    /// the test → RED; one that records in matrix order as it goes writes `[one, two]` → RED; a
    /// report built in finish order reads `[two, one]` → RED; a repetition line that waits for the
    /// loop to end, or counts the calls of other repetitions, misses `calls: 2` → RED.
    @Test(.timeLimit(.minutes(1)))
    func finishedCallIsRecordedAtOnceAndLandsInItsMatrixSlot() async {
        let samples = [
            CleanupBenchmarkSample(id: "one", raw: "one", references: ["one"]),
            CleanupBenchmarkSample(id: "two", raw: "two", references: ["two"]),
        ]
        let gate = Gate()
        let candidate = CleanupBenchmarkCandidate(provider: "fake", model: "m", lane: "m", width: 2) { raw, _, _, _ in
            if raw == "one" {
                await gate.wait()
            }
            return CleanupBenchmarkCleaned(text: raw)
        }
        let recorded = Mutex<[String]>([])
        let events = Mutex<[CleanupBenchmarkProgress]>([])

        let report = await CleanupBenchmarkRunner().run(
            candidates: [candidate],
            samples: samples,
            config: CleanupConfig(model: "unused", writingStyle: .casual),
            record: { run in
                recorded.withLock { $0.append(run.sampleId) }
                if run.sampleId == "two" {
                    gate.open()
                }
            },
            progress: { event in events.withLock { $0.append(event) } }
        )

        #expect(recorded.withLock { $0 } == ["two", "one"])
        #expect(report.runs.map(\.sampleId) == ["one", "two"])
        #expect(events.withLock { $0 }.contains(.repetitionFinished(repetition: 1, total: 1, calls: 2, failed: 0)))
    }

    /// One sample, one candidate that fails with `error` for its first `failures` calls and then
    /// answers. The sleeper records the waits it is asked for and returns at once.
    private static func runRateLimited(
        failures: Int,
        error: any Error,
        timer: CleanupBenchmarkTimer = .continuous
    ) async -> (report: CleanupBenchmarkReport, calls: Int, waits: [Double], events: [CleanupBenchmarkProgress], recorded: Int) {
        let calls = Mutex(0)
        let waits = Mutex<[Double]>([])
        let events = Mutex<[CleanupBenchmarkProgress]>([])
        let recorded = Mutex(0)
        let candidate = CleanupBenchmarkCandidate(provider: "fake", model: "m") { raw, _, _, _ in
            guard calls.withLock({ $0 += 1; return $0 }) > failures else { throw error }
            return CleanupBenchmarkCleaned(text: raw)
        }
        let report = await CleanupBenchmarkRunner(timer: timer, sleep: { seconds in waits.withLock { $0.append(seconds) } }).run(
            candidates: [candidate],
            samples: [CleanupBenchmarkSample(id: "s", raw: "Hello.", references: ["Hello."])],
            config: CleanupConfig(model: "unused", writingStyle: .casual),
            record: { _ in recorded.withLock { $0 += 1 } },
            progress: { event in events.withLock { $0.append(event) } }
        )
        return (report, calls.withLock { $0 }, waits.withLock { $0 }, events.withLock { $0 }, recorded.withLock { $0 })
    }

    /// Stated sensitivity: a runner that never repeats a rate-limited call records `provider-error` and
    /// no wait → RED; one that repeats it but waits the policy's backoff instead of the reply's
    /// `Retry-After` asks for 1 s, not 7 → RED; a retry count left at 0 misses `retried: 1` on both
    /// finish lines → RED; one that records the failed attempt as well records twice → RED.
    @Test
    func rateLimitedCallWaitsAsTheReplyAsksAndIsMadeAgain() async {
        let (report, calls, waits, events, recorded) = await Self.runRateLimited(failures: 1, error: CleanupError.rateLimited(retryAfter: 7))

        #expect(waits == [7])
        #expect(calls == 2)
        #expect(recorded == 1)
        #expect(report.runs.map(\.failures) == [[]])
        #expect(report.runs.map(\.errorKind) == [nil])
        #expect(events.contains(.candidateFinished(candidate: "fake:m", calls: 1, failed: 0, rateLimits: .init(retried: 1, gaveUp: 0))))
        #expect(events.last == .cleanupFinished(calls: 1, failed: 0, rateLimits: .init(retried: 1, gaveUp: 0)))
    }

    /// Stated sensitivity: a runner that retries without a bound never ends; one that gives up one
    /// attempt early or late asks the sleeper for another number of waits → RED; a give-up count left
    /// at 0 → RED; a run that does not end as `provider-error` with the coarse kind → RED.
    @Test
    func persistentRateLimitEndsAsAProviderErrorAfterTheAttemptsAreUsedUp() async {
        let attempts = CleanupBenchmarkRetryPolicy.attempts
        let (report, calls, waits, events, _) = await Self.runRateLimited(failures: .max, error: CleanupError.rateLimited(retryAfter: nil))

        #expect(calls == attempts)
        #expect(waits.count == attempts - 1)
        #expect(report.runs.map(\.failures) == [["provider-error"]])
        #expect(report.runs.map(\.errorKind) == [.providerError])
        #expect(events.contains(.candidateFinished(candidate: "fake:m", calls: 1, failed: 1, rateLimits: .init(retried: attempts - 1, gaveUp: 1))))
        #expect(events.last == .cleanupFinished(calls: 1, failed: 1, rateLimits: .init(retried: attempts - 1, gaveUp: 1)))
    }

    /// Stated sensitivity: a runner that repeats any error, not only a rate limit, calls twice and
    /// waits → RED.
    @Test
    func otherErrorIsNotMadeAgain() async {
        let (report, calls, waits, events, _) = await Self.runRateLimited(failures: .max, error: CleanupError.refused)

        #expect(calls == 1)
        #expect(waits.isEmpty)
        #expect(report.runs.map(\.errorKind) == [.providerError])
        #expect(events.last == .cleanupFinished(calls: 1, failed: 1, rateLimits: .init()))
    }

    /// Stated sensitivity: a timer wrapped around the whole retry loop reports the first attempt's
    /// 100 (the wait is inside it); a run that keeps the first attempt's duration reads 100 → RED.
    /// The fake timer takes the next duration at the start of each attempt, whether it fails or not.
    @Test
    func durationIsTheSuccessfulAttemptsAlone() async {
        let durations = Mutex<[UInt64]>([100, 5])
        let timer = CleanupBenchmarkTimer { operation in
            let duration = durations.withLock { $0.removeFirst() }
            let cleaned = try await operation()
            return TimedCleanupOutput(output: cleaned.text, durationNanoseconds: duration)
        }

        let (report, _, waits, _, _) = await Self.runRateLimited(failures: 1, error: CleanupError.rateLimited(retryAfter: 7), timer: timer)

        #expect(waits == [7])
        #expect(report.runs.map(\.durationNanoseconds) == [5])
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
