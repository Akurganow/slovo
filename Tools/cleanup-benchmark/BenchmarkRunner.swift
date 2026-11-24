import Foundation
import SlovoCore

/// The three coefficients of one output against its sample's reference, each in
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
    public let errorKind: CleanupBenchmarkErrorKind?

    public init(
        sampleId: String,
        sampleCategory: CleanupBenchmarkCategory = .uncategorized,
        sampleIndex: Int = 1,
        candidateName: String,
        repetition: Int = 1,
        durationNanoseconds: UInt64,
        output: String? = nil,
        scores: CleanupBenchmarkScores = CleanupBenchmarkScores(),
        failures: [String] = [],
        errorKind: CleanupBenchmarkErrorKind?
    ) {
        self.sampleId = sampleId
        self.sampleCategory = sampleCategory
        self.sampleIndex = sampleIndex
        self.candidateName = candidateName
        self.repetition = repetition
        self.durationNanoseconds = durationNanoseconds
        self.output = output
        self.scores = scores
        self.failures = failures
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
        context: PersonalizationContext,
        repetitions: Int = 1,
        warmupRepetitions: Int = 0,
        previous: [CleanupBenchmarkRunKey: CleanupBenchmarkRun] = [:],
        record: @Sendable (CleanupBenchmarkRun) -> Void = { _ in }
    ) async -> CleanupBenchmarkReport {
        let safeRepetitions = max(repetitions, 1)
        // A resumed run is not a cold start: warmup applies to a fresh run only.
        let safeWarmupRepetitions = previous.isEmpty ? max(warmupRepetitions, 0) : 0
        var runs: [CleanupBenchmarkRun] = []

        for _ in 0..<safeWarmupRepetitions {
            for sample in samples {
                for candidate in candidates {
                    await warmCandidate(
                        candidate,
                        sample: sample,
                        config: candidateConfig(for: candidate, base: config),
                        context: context
                    )
                }
            }
        }

        for repetition in 1...safeRepetitions {
            for (index, sample) in samples.enumerated() {
                for candidate in candidates {
                    let key = CleanupBenchmarkRunKey(candidateName: candidate.name, sampleId: sample.id, repetition: repetition)
                    if let earlier = previous[key], earlier.output != nil {
                        runs.append(earlier)
                        continue
                    }
                    let run = await runCandidate(
                        candidate,
                        sample: sample,
                        position: RunPosition(sampleIndex: index + 1, repetition: repetition),
                        config: candidateConfig(for: candidate, base: config),
                        context: context
                    )
                    record(run)
                    runs.append(run)
                }
            }
        }

        return CleanupBenchmarkReport(runs: runs)
    }

    private func candidateConfig(for candidate: CleanupBenchmarkCandidate, base: CleanupConfig) -> CleanupConfig {
        CleanupConfig(
            model: candidate.model,
            writingStyle: base.writingStyle
        )
    }

    private func warmCandidate(
        _ candidate: CleanupBenchmarkCandidate,
        sample: CleanupBenchmarkSample,
        config: CleanupConfig,
        context: PersonalizationContext
    ) async {
        _ = try? await candidate.cleaner.clean(sample.raw, config: config, context: context)
    }

    private func runCandidate(
        _ candidate: CleanupBenchmarkCandidate,
        sample: CleanupBenchmarkSample,
        position: RunPosition,
        config: CleanupConfig,
        context: PersonalizationContext
    ) async -> CleanupBenchmarkRun {
        do {
            let timed = try await timer.measure {
                try await candidate.cleaner.clean(sample.raw, config: config, context: context)
            }
            let isEmpty = timed.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return CleanupBenchmarkRun(
                sampleId: sample.id,
                sampleCategory: sample.category,
                sampleIndex: position.sampleIndex,
                candidateName: candidate.name,
                repetition: position.repetition,
                durationNanoseconds: timed.durationNanoseconds,
                output: timed.output,
                scores: CleanupBenchmarkScores(fuzzy: FuzzyScore.tokenSort(timed.output, sample.reference)),
                failures: isEmpty ? ["empty-output"] : [],
                errorKind: nil
            )
        } catch {
            return CleanupBenchmarkRun(
                sampleId: sample.id,
                sampleCategory: sample.category,
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
