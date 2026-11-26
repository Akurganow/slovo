import Foundation
import SlovoCore

/// The three coefficients of one output against its sample's references (the best of them), each in
/// 0...1 where 1 is identical. `embedding` and `jev` stay nil until the judge ran.
public struct CleanupBenchmarkScores: Equatable, Sendable {
    public var fuzzy: Double?
    public var embedding: Double?
    /// The lowest of the questions' means over the repeats.
    public var jev: Double?
    /// Every repeat's answer, by question key.
    public var jevQuestions: [String: [Double]]
    /// The response models that scored this output: the dated Jev snapshots and the
    /// embedding models, sorted.
    public var models: [String]

    public init(
        fuzzy: Double? = nil,
        embedding: Double? = nil,
        jev: Double? = nil,
        jevQuestions: [String: [Double]] = [:],
        models: [String] = []
    ) {
        self.fuzzy = fuzzy
        self.embedding = embedding
        self.jev = jev
        self.jevQuestions = jevQuestions
        self.models = models
    }
}

public struct CleanupBenchmarkRun: Equatable, Sendable {
    public let sampleId: String
    public let sampleCategory: CleanupBenchmarkCategory
    /// The sample's `language`; it makes a row of the bar only in the two language categories.
    public let sampleLanguage: String?
    /// 1-based position of the sample in the dataset.
    public let sampleIndex: Int
    public let candidateName: String
    /// 1-based.
    public let repetition: Int
    public let durationNanoseconds: UInt64
    /// Nil when the provider failed.
    public let output: String?
    public var scores: CleanupBenchmarkScores
    /// Coarse failure codes: `provider-error`, `empty-output`, and the judge's
    /// `embedding-failed`, `jev-refusal`, `jev-request-failed`.
    public var failures: [String]
    /// What the provider charged for the cleanup call; nil after a provider error or when it named no cost.
    public let costUSD: Double?
    public let errorKind: CleanupBenchmarkErrorKind?

    public init(
        sampleId: String,
        sampleCategory: CleanupBenchmarkCategory = .uncategorized,
        sampleLanguage: String? = nil,
        sampleIndex: Int = 1,
        candidateName: String,
        repetition: Int = 1,
        durationNanoseconds: UInt64,
        output: String? = nil,
        scores: CleanupBenchmarkScores = CleanupBenchmarkScores(),
        failures: [String] = [],
        costUSD: Double? = nil,
        errorKind: CleanupBenchmarkErrorKind?
    ) {
        self.sampleId = sampleId
        self.sampleCategory = sampleCategory
        self.sampleLanguage = sampleLanguage
        self.sampleIndex = sampleIndex
        self.candidateName = candidateName
        self.repetition = repetition
        self.durationNanoseconds = durationNanoseconds
        self.output = output
        self.scores = scores
        self.failures = failures
        self.costUSD = costUSD
        self.errorKind = errorKind
    }
}

/// Identifies one run across processes: the outputs file is keyed by it.
public struct CleanupBenchmarkRunKey: Hashable, Sendable {
    public let candidateName: String
    public let sampleId: String
    public let repetition: Int
}

public extension CleanupBenchmarkRun {
    var key: CleanupBenchmarkRunKey {
        CleanupBenchmarkRunKey(candidateName: candidateName, sampleId: sampleId, repetition: repetition)
    }

    static let emptyOutputCode = "empty-output"

    /// The candidate answered with nothing. That is its own failure: neither a repeat of
    /// the judge nor a resume changes it.
    var hasEmptyOutput: Bool {
        failures.contains(Self.emptyOutputCode)
    }

    /// The run as a fuzzy-only report sees it: no embedding, Jev score or judge failure code.
    func withoutJudgeResults() -> CleanupBenchmarkRun {
        var run = self
        run.scores = CleanupBenchmarkScores(fuzzy: scores.fuzzy)
        run.failures.removeAll { CleanupBenchmarkJudge.ownFailures.contains($0) }
        return run
    }

    /// A run that needs no more work: it has an output, no failure and every
    /// coefficient the benchmark was asked for.
    func isComplete(judged: Bool) -> Bool {
        output != nil && failures.isEmpty && scores.fuzzy != nil
            && (!judged || (scores.embedding != nil && scores.jev != nil))
    }
}

public enum CleanupBenchmarkErrorKind: String, Equatable, Sendable {
    case providerError = "provider-error"
}

/// The cleanup calls this process made, and how many of them ended in a failure code.
private struct CleanupTally {
    var calls = 0
    var failed = 0

    mutating func add(_ run: CleanupBenchmarkRun) {
        calls += 1
        if !run.failures.isEmpty { failed += 1 }
    }
}

/// Where a run sits in the matrix: both counted from 1.
private struct RunPosition {
    let sampleIndex: Int
    let repetition: Int
}

public struct CleanupBenchmarkRunner: Sendable {
    private let timer: CleanupBenchmarkTimer

    public init(timer: CleanupBenchmarkTimer = .continuous) {
        self.timer = timer
    }

    @preconcurrency
    public func run(
        candidates: [CleanupBenchmarkCandidate],
        samples: [CleanupBenchmarkSample],
        config: CleanupConfig,
        repetitions: Int = 1,
        warmupRepetitions: Int = 0,
        previous: [CleanupBenchmarkRunKey: CleanupBenchmarkRun] = [:],
        record: @Sendable (CleanupBenchmarkRun) -> Void = { _ in },
        progress: @Sendable (CleanupBenchmarkProgress) -> Void = { _ in }
    ) async -> CleanupBenchmarkReport {
        let safeRepetitions = max(repetitions, 1)
        var runs: [CleanupBenchmarkRun] = []

        for _ in 0..<max(warmupRepetitions, 0) {
            for sample in samples {
                for candidate in candidates {
                    await warmCandidate(
                        candidate,
                        sample: sample,
                        config: sample.cleanupConfig(model: candidate.model, style: config.writingStyle)
                    )
                }
            }
        }

        func isKept(_ candidate: CleanupBenchmarkCandidate, _ sample: CleanupBenchmarkSample, _ repetition: Int) -> CleanupBenchmarkRun? {
            let key = CleanupBenchmarkRunKey(candidateName: candidate.name, sampleId: sample.id, repetition: repetition)
            return previous[key].flatMap { $0.output == nil ? nil : $0 }
        }
        var keptByCandidate: [String: Int] = [:]
        for candidate in candidates {
            for sample in samples {
                keptByCandidate[candidate.name, default: 0] += (1...safeRepetitions).filter { isKept(candidate, sample, $0) != nil }.count
            }
        }
        let callsPerCandidate = samples.count * safeRepetitions
        let kept = keptByCandidate.values.reduce(0, +)
        progress(.cleanupStarted(
            candidates: candidates.count,
            samples: samples.count,
            repetitions: safeRepetitions,
            kept: kept
        ))
        for candidate in candidates where keptByCandidate[candidate.name] == callsPerCandidate {
            progress(.candidateKept(candidate: candidate.name, kept: callsPerCandidate))
        }

        var total = CleanupTally()
        var byCandidate: [String: CleanupTally] = [:]
        for repetition in 1...safeRepetitions {
            var inRepetition = CleanupTally()
            for (index, sample) in samples.enumerated() {
                for candidate in candidates {
                    if let earlier = isKept(candidate, sample, repetition) {
                        runs.append(earlier)
                        continue
                    }
                    if byCandidate[candidate.name] == nil {
                        progress(.candidateStarted(candidate: candidate.name))
                    }
                    let run = await runCandidate(
                        candidate,
                        sample: sample,
                        position: RunPosition(sampleIndex: index + 1, repetition: repetition),
                        config: sample.cleanupConfig(model: candidate.model, style: config.writingStyle)
                    )
                    record(run)
                    runs.append(run)
                    total.add(run)
                    inRepetition.add(run)
                    byCandidate[candidate.name, default: CleanupTally()].add(run)
                    if let tally = byCandidate[candidate.name],
                       tally.calls == callsPerCandidate - (keptByCandidate[candidate.name] ?? 0) {
                        progress(.candidateFinished(candidate: candidate.name, calls: tally.calls, failed: tally.failed))
                    }
                }
            }
            if inRepetition.calls > 0 {
                progress(.repetitionFinished(
                    repetition: repetition, total: safeRepetitions, calls: inRepetition.calls, failed: inRepetition.failed
                ))
            }
        }
        progress(.cleanupFinished(calls: total.calls, failed: total.failed))

        return CleanupBenchmarkReport(runs: runs)
    }

    private func warmCandidate(
        _ candidate: CleanupBenchmarkCandidate,
        sample: CleanupBenchmarkSample,
        config: CleanupConfig
    ) async {
        _ = try? await candidate.clean(sample.raw, config, sample.personalization, sample.hints)
    }

    private func runCandidate(
        _ candidate: CleanupBenchmarkCandidate,
        sample: CleanupBenchmarkSample,
        position: RunPosition,
        config: CleanupConfig
    ) async -> CleanupBenchmarkRun {
        do {
            let timed = try await timer.measure {
                try await candidate.clean(sample.raw, config, sample.personalization, sample.hints)
            }
            let isEmpty = timed.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return CleanupBenchmarkRun(
                sampleId: sample.id,
                sampleCategory: sample.category,
                sampleLanguage: sample.language,
                sampleIndex: position.sampleIndex,
                candidateName: candidate.name,
                repetition: position.repetition,
                durationNanoseconds: timed.durationNanoseconds,
                output: timed.output,
                scores: CleanupBenchmarkScores(fuzzy: FuzzyScore.best(timed.output, sample.references)),
                failures: isEmpty ? [CleanupBenchmarkRun.emptyOutputCode] : [],
                costUSD: timed.costUSD,
                errorKind: nil
            )
        } catch {
            return CleanupBenchmarkRun(
                sampleId: sample.id,
                sampleCategory: sample.category,
                sampleLanguage: sample.language,
                sampleIndex: position.sampleIndex,
                candidateName: candidate.name,
                repetition: position.repetition,
                durationNanoseconds: 0,
                failures: ["provider-error"],
                errorKind: .providerError
            )
        }
    }
}
