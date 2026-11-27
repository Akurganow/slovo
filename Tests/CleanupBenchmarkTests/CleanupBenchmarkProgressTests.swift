import Foundation
import Synchronization
import Testing

import CleanupBenchmark
import SlovoCore

@Suite("Cleanup benchmark progress and cost")
struct CleanupBenchmarkProgressTests {
    private static let samples = [
        CleanupBenchmarkSample(id: "one", raw: "Hello.", references: ["Hello."]),
        CleanupBenchmarkSample(id: "two", raw: "Hello.", references: ["Hello."]),
    ]

    private static func run(
        _ candidates: [CleanupBenchmarkCandidate],
        samples: [CleanupBenchmarkSample] = samples,
        repetitions: Int,
        previous: [CleanupBenchmarkRunKey: CleanupBenchmarkRun] = [:]
    ) async -> (report: CleanupBenchmarkReport, events: [CleanupBenchmarkProgress]) {
        let events = Mutex<[CleanupBenchmarkProgress]>([])
        let report = await CleanupBenchmarkRunner().run(
            candidates: candidates,
            samples: samples,
            config: CleanupConfig(model: "unused", writingStyle: .casual),
            repetitions: repetitions,
            previous: previous,
            progress: { event in events.withLock { $0.append(event) } }
        )
        return (report, events.withLock { $0 })
    }

    private static func kept(_ candidate: String, _ sample: String, _ repetition: Int) -> (CleanupBenchmarkRunKey, CleanupBenchmarkRun) {
        let run = CleanupBenchmarkRun(
            sampleId: sample, candidateName: candidate, repetition: repetition, durationNanoseconds: 1, output: "Hello.", errorKind: nil
        )
        return (run.key, run)
    }

    /// Two candidates, two samples, two repetitions, one failing call and one run kept from `previous`.
    ///
    /// Stated sensitivity: a candidate start taken from the matrix position (the first cell of
    /// repetition 1), not from its first call made here, announces `fake:a` before `fake:b` although
    /// its first cell is the kept run → RED; a runner that counts the kept run as a call reports
    /// `kept: 0` and ends `fake:a` after 4 calls → RED; a tally that never counts a failure leaves `failed: 1` out of the repetition and
    /// candidate lines → RED.
    @Test
    func runnerEmitsOneEventPerStageOfTheMatrix() async {
        let failures = Mutex(0)
        let first = CleanupBenchmarkCandidate(provider: "fake", model: "a", cleaner: CountingCleaner(output: "Hello.", called: {}))
        let second = CleanupBenchmarkCandidate(
            provider: "fake",
            model: "b",
            cleaner: CountingCleaner(output: "Hello.", called: {}, fails: { failures.withLock { $0 += 1; return $0 == 2 } })
        )
        let (key, earlier) = Self.kept("fake:a", "one", 1)

        let (report, events) = await Self.run([first, second], repetitions: 2, previous: [key: earlier])

        #expect(report.runs.count == 8)
        #expect(events == [
            .cleanupStarted(candidates: 2, samples: 2, repetitions: 2, kept: 1),
            .candidateStarted(candidate: "fake:b"),
            .candidateStarted(candidate: "fake:a"),
            .repetitionFinished(repetition: 1, total: 2, calls: 3, failed: 1),
            .candidateFinished(candidate: "fake:a", calls: 3, failed: 0, rateLimits: .init()),
            .candidateFinished(candidate: "fake:b", calls: 4, failed: 1, rateLimits: .init()),
            .repetitionFinished(repetition: 2, total: 2, calls: 4, failed: 0),
            .cleanupFinished(calls: 7, failed: 1, rateLimits: .init()),
        ])
    }

    /// Stated sensitivity: a repetition line for a repetition in which this process made no call
    /// (`calls: 0`) → RED; a candidate with every run kept that still announces a start and a
    /// finish, or none that it has no call to make → RED.
    @Test
    func candidateWithEveryRunKeptSaysSoAndAnEmptyRepetitionIsSilent() async {
        let first = CleanupBenchmarkCandidate(provider: "fake", model: "a", cleaner: CountingCleaner(output: "Hello.", called: {}))
        let second = CleanupBenchmarkCandidate(provider: "fake", model: "b", cleaner: CountingCleaner(output: "Hello.", called: {}))
        let previous = Dictionary(uniqueKeysWithValues: [
            Self.kept("fake:a", "one", 1), Self.kept("fake:a", "one", 2), Self.kept("fake:b", "one", 1),
        ])

        let (_, events) = await Self.run([first, second], samples: [Self.samples[0]], repetitions: 2, previous: previous)

        #expect(events == [
            .cleanupStarted(candidates: 2, samples: 1, repetitions: 2, kept: 3),
            .candidateKept(candidate: "fake:a", kept: 2),
            .candidateStarted(candidate: "fake:b"),
            .candidateFinished(candidate: "fake:b", calls: 1, failed: 0, rateLimits: .init()),
            .repetitionFinished(repetition: 2, total: 2, calls: 1, failed: 0),
            .cleanupFinished(calls: 1, failed: 0, rateLimits: .init()),
        ])
    }

    /// Stated sensitivity: a runner that drops `timed.costUSD`, or a default timer that drops the
    /// cost of the cleaning it measured, leaves every run without cost → RED; a failed call that
    /// keeps the cost of an earlier one → RED.
    @Test
    func runCarriesTheCostOfItsCallAndAFailedCallHasNone() async {
        let calls = Mutex(0)
        let candidate = CleanupBenchmarkCandidate(provider: "fake", model: "paid") { _, _, _, _ in
            guard calls.withLock({ $0 += 1; return $0 }) == 1 else { throw SensitiveError(payload: "provider down") }
            return CleanupBenchmarkCleaned(text: "Hello.", costUSD: 0.25)
        }

        let (report, _) = await Self.run([candidate], samples: [Self.samples[0]], repetitions: 2)

        #expect(report.runs.map(\.costUSD) == [0.25, nil])
        #expect(report.runs.map(\.errorKind) == [nil, .providerError])
    }

    /// Stated sensitivity: candidates taken in dictionary order, not by name, or `runs` counted over
    /// every run handed in (the run with no output is not judged), or a failed count fixed at 0
    /// → RED.
    @Test
    func judgeEmitsEventsPerCandidateWithJudgedAndFailedCounts() async throws {
        func run(_ candidate: String, _ sample: String, output: String?) -> CleanupBenchmarkRun {
            CleanupBenchmarkRun(
                sampleId: sample, candidateName: candidate, durationNanoseconds: 1, output: output,
                scores: CleanupBenchmarkScores(fuzzy: 1), errorKind: nil
            )
        }
        let runs = [
            run("fake:good", "one", output: "Hello there."),
            run("fake:bad", "one", output: "WRONG text."),
            run("fake:good", "two", output: "Hello there."),
            run("fake:bad", "two", output: "WRONG text."),
            run("fake:good", "three", output: nil),
        ]
        let samples = [
            CleanupBenchmarkSample(id: "one", raw: "Hello.", references: ["Hello there."]),
            CleanupBenchmarkSample(id: "two", raw: "Hello.", references: ["Hello there."]),
            CleanupBenchmarkSample(id: "three", raw: "Hello.", references: ["Hello there."]),
        ]
        let judge = CleanupBenchmarkJudge(transport: FakeJudgeTransport(failingDecisionsFor: "WRONG"), settings: try judgeSettings())
        let events = Mutex<[CleanupBenchmarkProgress]>([])

        let scored = await judge.score(runs, samples: samples, progress: { event in events.withLock { $0.append(event) } })

        #expect(scored.info.costUSD > 0)
        #expect(events.withLock { $0 } == [
            .judgeStarted(runs: 4),
            .judgeCandidateStarted(candidate: "fake:bad", runs: 2),
            .judgeCandidateFinished(candidate: "fake:bad", judged: 2, failed: 2),
            .judgeCandidateStarted(candidate: "fake:good", runs: 2),
            .judgeCandidateFinished(candidate: "fake:good", judged: 2, failed: 0),
            .judgeFinished(judged: 4, failed: 2, costUSD: scored.info.costUSD),
        ])
    }

    /// Stated sensitivity: a command that never hands its sink to the runner, the judge or the
    /// baseline write leaves that stage silent; a baseline line that counts the candidates asked
    /// for, not the entries written, reads `written: 2` here → RED.
    @Test
    func commandSendsEveryStageToItsSink() async throws {
        let fixture = try DriverFixture(
            files: ["baseline.json": #"{"version":1,"candidates":{}}"#],
            transport: FakeJudgeTransport(failingDecisionsFor: "WRONG")
        )

        _ = await fixture.run([
            "--providers", "openrouter:good,openrouter:bad", "--judge", "--write-baseline", "baseline.json",
        ])

        let repetitions = try judgeSettings().bar.repetitions
        let events = fixture.progress
        #expect(events.first == .cleanupStarted(candidates: 2, samples: 2, repetitions: repetitions, kept: 0))
        #expect(events.contains(.cleanupFinished(calls: 4 * repetitions, failed: 0, rateLimits: .init())))
        #expect(events.contains(.judgeStarted(runs: 4 * repetitions)))
        #expect(events.suffix(2) == [.baselineWriteStarted, .baselineWriteFinished(written: 1, notWritten: 1)])
    }

    /// Stated sensitivity: a line that loses the `progress: ` prefix breaks what a log reader greps
    /// by, and two events worded alike hide a stage from it → RED; a finish line that leaves out
    /// the retry count or the give-up count, or swaps them, misses its suffix → RED.
    @Test
    func everyEventHasTheGreppablePrefixAndItsOwnWording() {
        let events: [CleanupBenchmarkProgress] = [
            .cleanupStarted(candidates: 1, samples: 2, repetitions: 3, kept: 5),
            .candidateStarted(candidate: "fake:a"),
            .repetitionFinished(repetition: 1, total: 2, calls: 3, failed: 0),
            .candidateFinished(candidate: "fake:a", calls: 3, failed: 1, rateLimits: .init(retried: 2, gaveUp: 1)),
            .candidateKept(candidate: "fake:a", kept: 3),
            .cleanupFinished(calls: 3, failed: 1, rateLimits: .init(retried: 2, gaveUp: 1)),
            .judgeStarted(runs: 3),
            .judgeCandidateStarted(candidate: "fake:a", runs: 3),
            .judgeCandidateFinished(candidate: "fake:a", judged: 3, failed: 0),
            .judgeFinished(judged: 3, failed: 0, costUSD: 0.5),
            .baselineWriteStarted,
            .baselineWriteFinished(written: 1, notWritten: 0),
        ]
        for event in events {
            #expect(event.line.hasPrefix("progress: "))
        }
        #expect(Set(events.map(\.line)).count == events.count)
        // 1 candidate × 2 samples × 3 repetitions less 5 kept runs.
        #expect(events[0].line.contains("calls to make 1,"))
        for finished in [events[3], events[5]] {
            #expect(finished.line.hasSuffix("failed 1, retried after a rate limit 2, gave up after rate limits 1"))
        }
    }

    /// Stated sensitivity: a sum that counts a run without a cost as zero prints `0.000000` for
    /// the row with none; a row that leaves out the runs of one repetition, or the category
    /// breakdown that does not follow the summary's columns → RED.
    @Test
    func costColumnSumsTheRunsThatHaveOne() {
        func run(_ candidate: String, cost: Double?) -> CleanupBenchmarkRun {
            CleanupBenchmarkRun(sampleId: "s", candidateName: candidate, durationNanoseconds: 1, output: "x", costUSD: cost, errorKind: nil)
        }
        let report = CleanupBenchmarkReport(runs: [
            run("paid", cost: 0.000002), run("paid", cost: 0.000003), run("paid", cost: nil),
            run("unknown", cost: nil),
            run("free", cost: 0), run("free", cost: 0),
        ])

        let rows = CleanupBenchmarkReportFormatter.render(report).split(separator: "\n").map(String.init)
        let categories = CleanupBenchmarkReportFormatter.renderCategoryBreakdown(report).split(separator: "\n").map(String.init)

        #expect(rows[0].hasSuffix(",jev,cost_usd"))
        #expect(rows[1].hasPrefix("paid,3,0,") && rows[1].hasSuffix(",0.000005"))
        #expect(rows[2].hasPrefix("unknown,1,0,") && rows[2].hasSuffix(",,,"))
        #expect(rows[3].hasPrefix("free,2,0,") && rows[3].hasSuffix(",0.000000"))
        #expect(categories[0].hasSuffix(",jev,cost_usd"))
        #expect(categories.first { $0.hasPrefix("paid,") }?.hasSuffix(",0.000005") == true)
    }
}
