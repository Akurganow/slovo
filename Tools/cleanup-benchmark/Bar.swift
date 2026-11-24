import Foundation

/// A coefficient's slack (1 − coefficient) on one sample across a candidate's
/// repetitions: its mean, and its spread (largest minus smallest).
public struct CleanupBenchmarkSlack: Codable, Equatable, Sendable {
    public let mean: Double
    public let spread: Double

    public init(mean: Double, spread: Double) {
        self.mean = mean
        self.spread = spread
    }
}

public struct CleanupBenchmarkBaselineSample: Codable, Equatable, Sendable {
    public let fuzzy: CleanupBenchmarkSlack
    public let embedding: CleanupBenchmarkSlack
    public let jev: CleanupBenchmarkSlack

    public init(fuzzy: CleanupBenchmarkSlack, embedding: CleanupBenchmarkSlack, jev: CleanupBenchmarkSlack) {
        self.fuzzy = fuzzy
        self.embedding = embedding
        self.jev = jev
    }
}

/// One model's recorded slack against the shared references, with the judge that
/// measured it.
public struct CleanupBenchmarkBaselineEntry: Codable, Equatable, Sendable {
    public let jevModel: String
    /// The `model` field of the Jev responses: the dated snapshots that answered.
    public let jevSnapshots: [String]
    public let embeddingModel: String
    public let embeddingResponseModels: [String]
    public let datasetSHA256: String
    /// By sample id.
    public let samples: [String: CleanupBenchmarkBaselineSample]

    public init(
        jevModel: String,
        jevSnapshots: [String],
        embeddingModel: String,
        embeddingResponseModels: [String],
        datasetSHA256: String,
        samples: [String: CleanupBenchmarkBaselineSample]
    ) {
        self.jevModel = jevModel
        self.jevSnapshots = jevSnapshots
        self.embeddingModel = embeddingModel
        self.embeddingResponseModels = embeddingResponseModels
        self.datasetSHA256 = datasetSHA256
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

public enum CleanupBenchmarkBarError: Error, Equatable, Sendable {
    /// Every run behind a baseline must be fully scored: an unscored run has no slack.
    case unscoredRuns(candidate: String, count: Int)
}

public struct CleanupBenchmarkVerdictRow: Equatable, Sendable {
    /// Nil for the candidate's runs overall.
    public let category: CleanupBenchmarkCategory?
    public let runs: Int
    public let withinSlack: Int
    public let passed: Bool

    public var share: Double {
        runs == 0 ? 0 : Double(withinSlack) / Double(runs)
    }
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

/// The bar: a candidate's run on a sample is within today's slack when, for every
/// coefficient, its slack is at most the baseline's mean slack plus the larger of
/// the baseline's spread and the coefficient's floor. A candidate passes when its
/// within-slack share is at least the baseline's own share less the allowance,
/// overall and in every category.
public enum CleanupBenchmarkBar {
    /// The baseline's own runs are always within slack: a spread is never smaller
    /// than a run's distance from the mean. So the baseline's share is 1.
    static let baselineShare = 1.0
    private static let tolerance = 1e-9

    public static func slack(of runs: [CleanupBenchmarkRun]) -> CleanupBenchmarkBaselineSample? {
        let fuzzy = runs.compactMap(\.scores.fuzzy)
        let embedding = runs.compactMap(\.scores.embedding)
        let jev = runs.compactMap(\.scores.jev)
        guard !runs.isEmpty, fuzzy.count == runs.count, embedding.count == runs.count, jev.count == runs.count else {
            return nil
        }
        return CleanupBenchmarkBaselineSample(
            fuzzy: stats(fuzzy), embedding: stats(embedding), jev: stats(jev)
        )
    }

    /// The entry for one candidate from its runs over the dataset, every sample in
    /// every repetition fully scored.
    public static func makeEntry(
        candidateName: String,
        runs: [CleanupBenchmarkRun],
        settings: CleanupBenchmarkJudgeSettings,
        info: CleanupBenchmarkJudgeInfo,
        datasetSHA256: String
    ) throws -> CleanupBenchmarkBaselineEntry {
        let own = runs.filter { $0.candidateName == candidateName }
        var samples: [String: CleanupBenchmarkBaselineSample] = [:]
        var unscored = 0
        for (id, group) in Dictionary(grouping: own, by: \.sampleId) {
            if let sample = slack(of: group) {
                samples[id] = sample
            } else {
                unscored += group.count
            }
        }
        guard unscored == 0 else {
            throw CleanupBenchmarkBarError.unscoredRuns(candidate: candidateName, count: unscored)
        }
        return CleanupBenchmarkBaselineEntry(
            jevModel: settings.jev.model,
            jevSnapshots: info.jevModelIDs,
            embeddingModel: settings.embedding.model,
            embeddingResponseModels: info.embeddingModelIDs,
            datasetSHA256: datasetSHA256,
            samples: samples
        )
    }

    public static func isWithinSlack(
        _ scores: CleanupBenchmarkScores,
        baseline: CleanupBenchmarkBaselineSample,
        floors: CleanupBenchmarkJudgeSettings.Bar.Floors
    ) -> Bool {
        guard let fuzzy = scores.fuzzy, let embedding = scores.embedding, let jev = scores.jev else {
            return false
        }
        return within(1 - fuzzy, baseline.fuzzy, floor: floors.fuzzy)
            && within(1 - embedding, baseline.embedding, floor: floors.embedding)
            && within(1 - jev, baseline.jev, floor: floors.jev)
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
            let within = group.filter { run in
                entry.samples[run.sampleId].map { isWithinSlack(run.scores, baseline: $0, floors: settings.floors) } ?? false
            }.count
            let share = group.isEmpty ? 0 : Double(within) / Double(group.count)
            return CleanupBenchmarkVerdictRow(
                category: category,
                runs: group.count,
                withinSlack: within,
                passed: share + tolerance >= baselineShare - settings.allowance
            )
        }
        let categories = Set(own.map(\.sampleCategory)).sorted { $0.rawValue < $1.rawValue }
        return CleanupBenchmarkVerdict(
            candidateName: candidateName,
            baselineName: baselineName,
            rows: [row(nil, own)] + categories.map { category in row(category, own.filter { $0.sampleCategory == category }) }
        )
    }

    private static func within(_ slack: Double, _ baseline: CleanupBenchmarkSlack, floor: Double) -> Bool {
        slack <= baseline.mean + max(baseline.spread, floor) + tolerance
    }

    private static func stats(_ coefficients: [Double]) -> CleanupBenchmarkSlack {
        let slacks = coefficients.map { 1 - $0 }
        let mean = slacks.reduce(0, +) / Double(slacks.count)
        return CleanupBenchmarkSlack(mean: mean, spread: (slacks.max() ?? 0) - (slacks.min() ?? 0))
    }
}
