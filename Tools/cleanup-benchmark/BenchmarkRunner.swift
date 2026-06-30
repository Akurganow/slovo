import Foundation
import SlovoCore

public struct CleanupBenchmarkRun: Equatable, Sendable {
    public let sampleId: String
    public let sampleCategory: CleanupBenchmarkCategory
    public let candidateName: String
    public let durationNanoseconds: UInt64
    public let quality: CleanupQualityResult
    public let errorKind: CleanupBenchmarkErrorKind?

    public init(
        sampleId: String,
        sampleCategory: CleanupBenchmarkCategory = .uncategorized,
        candidateName: String,
        durationNanoseconds: UInt64,
        quality: CleanupQualityResult,
        errorKind: CleanupBenchmarkErrorKind?
    ) {
        self.sampleId = sampleId
        self.sampleCategory = sampleCategory
        self.candidateName = candidateName
        self.durationNanoseconds = durationNanoseconds
        self.quality = quality
        self.errorKind = errorKind
    }
}

public enum CleanupBenchmarkErrorKind: String, Equatable, Sendable {
    case providerError = "provider-error"
}

public struct CleanupBenchmarkRunner: Sendable {
    private let timer: CleanupBenchmarkTimer

    public init(timer: CleanupBenchmarkTimer = .continuous) {
        self.timer = timer
    }

    public func run(
        candidates: [CleanupBenchmarkCandidate],
        samples: [CleanupBenchmarkSample],
        config: CleanupConfig,
        context: PersonalizationContext,
        repetitions: Int = 1
    ) async -> CleanupBenchmarkReport {
        let safeRepetitions = max(repetitions, 1)
        var runs: [CleanupBenchmarkRun] = []

        for _ in 0..<safeRepetitions {
            for sample in samples {
                for candidate in candidates {
                    let candidateConfig = CleanupConfig(
                        model: candidate.model,
                        writingStyle: config.writingStyle,
                        language: config.language
                    )
                    runs.append(await runCandidate(
                        candidate,
                        sample: sample,
                        config: candidateConfig,
                        context: context
                    ))
                }
            }
        }

        return CleanupBenchmarkReport(runs: runs)
    }

    private func runCandidate(
        _ candidate: CleanupBenchmarkCandidate,
        sample: CleanupBenchmarkSample,
        config: CleanupConfig,
        context: PersonalizationContext
    ) async -> CleanupBenchmarkRun {
        do {
            let timed = try await timer.measure {
                try await candidate.cleaner.clean(sample.raw, config: config, context: context)
            }
            return CleanupBenchmarkRun(
                sampleId: sample.id,
                sampleCategory: sample.category,
                candidateName: candidate.name,
                durationNanoseconds: timed.durationNanoseconds,
                quality: CleanupQualityGate.evaluate(output: timed.output, sample: sample),
                errorKind: nil
            )
        } catch {
            return CleanupBenchmarkRun(
                sampleId: sample.id,
                sampleCategory: sample.category,
                candidateName: candidate.name,
                durationNanoseconds: 0,
                quality: CleanupQualityResult(passed: false, failures: ["provider-error"]),
                errorKind: .providerError
            )
        }
    }
}
