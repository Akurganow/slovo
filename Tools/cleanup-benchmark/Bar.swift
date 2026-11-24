import Foundation

/// One sample's recorded slack (1 − coefficient) per coefficient: the mean of the
/// repetitions' slacks after the `bar.dropWorst` largest are dropped.
public struct CleanupBenchmarkBaselineSample: Codable, Equatable, Sendable {
    public let fuzzy: Double
    public let embedding: Double
    public let jev: Double

    public init(fuzzy: Double, embedding: Double, jev: Double) {
        self.fuzzy = fuzzy
        self.embedding = embedding
        self.jev = jev
    }
}

/// One model's recorded slack against the shared references, with the judge that
/// measured it.
public struct CleanupBenchmarkBaselineEntry: Codable, Equatable, Sendable {
    /// `CleanupBenchmarkJudgeSettings.judgeSHA256()` of the judge that measured it.
    public let judgeSHA256: String
    /// The response models that scored this candidate's runs: the dated Jev
    /// snapshots and the embedding models.
    public let snapshots: [String]
    public let datasetSHA256: String
    /// The repetitions per sample that the slacks come from (`bar.repetitions`).
    public let repetitions: Int
    /// By sample id.
    public let samples: [String: CleanupBenchmarkBaselineSample]

    public init(
        judgeSHA256: String,
        snapshots: [String],
        datasetSHA256: String,
        repetitions: Int,
        samples: [String: CleanupBenchmarkBaselineSample]
    ) {
        self.judgeSHA256 = judgeSHA256
        self.snapshots = snapshots
        self.datasetSHA256 = datasetSHA256
        self.repetitions = repetitions
        self.samples = samples
    }
}

/// `Benchmarks/cleanup/baseline.json`: one entry per candidate name
/// (`provider:model`). A command writes it; nobody edits it.
public struct CleanupBenchmarkBaselineFile: Codable, Equatable, Sendable {
    public var candidates: [String: CleanupBenchmarkBaselineEntry]

    public init(candidates: [String: CleanupBenchmarkBaselineEntry] = [:]) {
        self.candidates = candidates
    }

    public static func decode(_ data: Data) throws -> CleanupBenchmarkBaselineFile {
        try JSONDecoder().decode(CleanupBenchmarkBaselineFile.self, from: data)
    }

    /// Keys sorted, so a rewrite changes only the entries that ran.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    /// The entries of `entries` replace those of the same name; all others stay.
    public func merging(_ entries: [String: CleanupBenchmarkBaselineEntry]) -> CleanupBenchmarkBaselineFile {
        CleanupBenchmarkBaselineFile(candidates: candidates.merging(entries) { _, new in new })
    }

    /// The entry a candidate is judged against: its own, else the named fallback's.
    public func entry(for candidateName: String, fallback: String) -> (name: String, entry: CleanupBenchmarkBaselineEntry)? {
        for name in [candidateName, fallback] {
            if let entry = candidates[name] {
                return (name, entry)
            }
        }
        return nil
    }
}

public enum CleanupBenchmarkBarError: Error, Equatable, CustomStringConvertible, Sendable {
    /// Every run behind an entry must be complete: an output, no failure, all three coefficients.
    case incompleteRuns(candidate: String, count: Int)
    /// A candidate's empty answer is its own failure: judging it again changes nothing.
    case emptyOutputs(candidate: String, count: Int)

    public var description: String {
        switch self {
        case .incompleteRuns(let candidate, let count):
            "no baseline entry for \(candidate): \(count) of its runs have no full score or carry a failure"
        case .emptyOutputs(let candidate, let count):
            "no baseline entry for \(candidate): \(count) of its runs returned an empty output, which judging again "
                + "does not change; run the candidate again with a new --outputs-file, or none"
        }
    }
}

/// Absorbs float error in two places: a slack compared with its limit, and
/// `allowance × samples` rounded down to a miss count (`0.05 × 60` is `3.0000000000000004`).
private let floatTolerance = 1e-9

public struct CleanupBenchmarkVerdictRow: Equatable, Sendable {
    /// Nil for the candidate's samples overall.
    public let category: CleanupBenchmarkCategory?
    public let samples: Int
    /// Samples not within slack.
    public let misses: Int
    public let allowedMisses: Int
    /// Dropped repetitions whose slack was outside the baseline's on some coefficient: the
    /// failures the bar tolerates, shown so they are not lost.
    public let droppedOutside: Int
    public let means: CleanupBenchmarkMeans
    public let passed: Bool
}

public struct CleanupBenchmarkVerdict: Equatable, Sendable {
    public let candidateName: String
    /// The candidate whose entry the runs were judged against.
    public let baselineName: String
    public let rows: [CleanupBenchmarkVerdictRow]

    public var passed: Bool {
        rows.allSatisfy(\.passed)
    }
}

/// The bar. Per sample and coefficient, the slack (1 − coefficient) is the mean over the
/// repetitions after the `dropWorst` largest are dropped; a baseline entry and a
/// candidate are measured the same way. A sample is within slack when, for every
/// coefficient, the candidate's slack is at most the entry's plus the coefficient's floor.
/// A candidate passes when the samples not within slack number at most the allowance's
/// share of the row's samples, and at least one, overall and in every category.
public enum CleanupBenchmarkBar {
    private typealias Coefficient = KeyPath<CleanupBenchmarkScores, Double?>
    private typealias Floors = CleanupBenchmarkJudgeSettings.Bar.Floors

    /// One coefficient's slacks over a sample's repetitions, the largest first. An unscored
    /// run has slack 1.
    private static func ranked(_ runs: [CleanupBenchmarkRun], _ coefficient: Coefficient) -> [(index: Int, slack: Double)] {
        runs.enumerated()
            .map { (index: $0.offset, slack: 1 - ($0.element.scores[keyPath: coefficient] ?? 0)) }
            .sorted { $0.slack != $1.slack ? $0.slack > $1.slack : $0.index < $1.index }
    }

    private static func trimmedMean(_ runs: [CleanupBenchmarkRun], _ coefficient: Coefficient, dropWorst: Int) -> Double {
        let kept = ranked(runs, coefficient).dropFirst(dropWorst).map(\.slack)
        return kept.isEmpty ? 1 : kept.reduce(0, +) / Double(kept.count)
    }

    /// The slack of one sample's runs.
    public static func slack(of runs: [CleanupBenchmarkRun], dropWorst: Int) -> CleanupBenchmarkBaselineSample {
        CleanupBenchmarkBaselineSample(
            fuzzy: trimmedMean(runs, \.fuzzy, dropWorst: dropWorst),
            embedding: trimmedMean(runs, \.embedding, dropWorst: dropWorst),
            jev: trimmedMean(runs, \.jev, dropWorst: dropWorst)
        )
    }

    /// The entry for one candidate from its runs over the dataset. Every run must be
    /// complete: an empty output or a judge failure would raise a slack and loosen the bar
    /// for good.
    public static func makeEntry(
        candidateName: String,
        runs: [CleanupBenchmarkRun],
        settings: CleanupBenchmarkJudgeSettings,
        datasetSHA256: String
    ) throws -> CleanupBenchmarkBaselineEntry {
        let own = runs.filter { $0.candidateName == candidateName }
        let empty = own.filter(\.hasEmptyOutput).count
        guard empty == 0 else {
            throw CleanupBenchmarkBarError.emptyOutputs(candidate: candidateName, count: empty)
        }
        let incomplete = own.filter { !$0.isComplete(judged: true) }.count
        guard incomplete == 0 else {
            throw CleanupBenchmarkBarError.incompleteRuns(candidate: candidateName, count: incomplete)
        }
        return CleanupBenchmarkBaselineEntry(
            judgeSHA256: try settings.judgeSHA256(),
            snapshots: Set(own.flatMap(\.scores.models)).sorted(),
            datasetSHA256: datasetSHA256,
            repetitions: settings.bar.repetitions,
            samples: Dictionary(
                uniqueKeysWithValues: Dictionary(grouping: own, by: \.sampleId)
                    .map { ($0, slack(of: $1, dropWorst: settings.bar.dropWorst)) }
            )
        )
    }

    /// Per coefficient, the slack a candidate may show: the recorded one plus the floor.
    private static func limits(_ recorded: CleanupBenchmarkBaselineSample, _ floors: Floors) -> [(coefficient: Coefficient, limit: Double)] {
        [
            (\.fuzzy, recorded.fuzzy + floors.fuzzy),
            (\.embedding, recorded.embedding + floors.embedding),
            (\.jev, recorded.jev + floors.jev),
        ]
    }

    /// One sample's runs against its recorded slack.
    public static func isWithinSlack(
        _ runs: [CleanupBenchmarkRun],
        baseline: CleanupBenchmarkBaselineSample,
        bar: CleanupBenchmarkJudgeSettings.Bar
    ) -> Bool {
        limits(baseline, bar.floors).allSatisfy { coefficient, limit in
            trimmedMean(runs, coefficient, dropWorst: bar.dropWorst) <= limit + floatTolerance
        }
    }

    /// Dropped repetitions of one sample that are outside the recorded slack on any coefficient.
    private static func droppedOutside(
        _ runs: [CleanupBenchmarkRun],
        baseline: CleanupBenchmarkBaselineSample,
        bar: CleanupBenchmarkJudgeSettings.Bar
    ) -> Int {
        var outside = Set<Int>()
        for (coefficient, limit) in limits(baseline, bar.floors) {
            for dropped in ranked(runs, coefficient).prefix(bar.dropWorst) where dropped.slack > limit + floatTolerance {
                outside.insert(dropped.index)
            }
        }
        return outside.count
    }

    public static func verdict(
        candidateName: String,
        baselineName: String,
        runs: [CleanupBenchmarkRun],
        entry: CleanupBenchmarkBaselineEntry,
        settings: CleanupBenchmarkJudgeSettings.Bar
    ) -> CleanupBenchmarkVerdict {
        let own = runs.filter { $0.candidateName == candidateName }
        func row(_ category: CleanupBenchmarkCategory?, _ group: [CleanupBenchmarkRun]) -> CleanupBenchmarkVerdictRow {
            let bySample = Dictionary(grouping: group, by: \.sampleId)
            var misses = 0
            var droppedOutside = 0
            for (id, sampleRuns) in bySample {
                guard let recorded = entry.samples[id] else {
                    misses += 1
                    continue
                }
                if !isWithinSlack(sampleRuns, baseline: recorded, bar: settings) {
                    misses += 1
                }
                droppedOutside += Self.droppedOutside(sampleRuns, baseline: recorded, bar: settings)
            }
            // At least one miss is always allowed, so a small row is not failed by a single
            // sample. A row with no samples has no verdict to pass.
            let allowedMisses = max(1, Int((settings.allowance * Double(bySample.count) + floatTolerance).rounded(.down)))
            return CleanupBenchmarkVerdictRow(
                category: category,
                samples: bySample.count,
                misses: misses,
                allowedMisses: allowedMisses,
                droppedOutside: droppedOutside,
                means: CleanupBenchmarkMeans(group),
                passed: !group.isEmpty && misses <= allowedMisses
            )
        }
        let categories = Set(own.map(\.sampleCategory)).sorted { $0.rawValue < $1.rawValue }
        return CleanupBenchmarkVerdict(
            candidateName: candidateName,
            baselineName: baselineName,
            rows: [row(nil, own)] + categories.map { category in row(category, own.filter { $0.sampleCategory == category }) }
        )
    }
}
