import Foundation

/// A coefficient's slack (1 − coefficient) on one sample: its mean across a
/// candidate's repetitions.
public struct CleanupBenchmarkSlack: Codable, Equatable, Sendable {
    public let mean: Double

    public init(mean: Double) {
        self.mean = mean
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
    /// `CleanupBenchmarkJudgeSettings.judgeSHA256()` of the judge that measured it.
    public let judgeSHA256: String
    /// The response models that scored this candidate's runs: the dated Jev
    /// snapshots and the embedding models.
    public let snapshots: [String]
    public let datasetSHA256: String
    /// By sample id.
    public let samples: [String: CleanupBenchmarkBaselineSample]

    public init(
        judgeSHA256: String,
        snapshots: [String],
        datasetSHA256: String,
        samples: [String: CleanupBenchmarkBaselineSample]
    ) {
        self.judgeSHA256 = judgeSHA256
        self.snapshots = snapshots
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

public enum CleanupBenchmarkBarError: Error, Equatable, CustomStringConvertible, Sendable {
    /// Every run behind an entry must be complete: an output, no failure, all three coefficients.
    case incompleteRuns(candidate: String, count: Int)

    public var description: String {
        switch self {
        case .incompleteRuns(let candidate, let count):
            "no baseline entry for \(candidate): \(count) of its runs have no full score or carry a failure; "
                + "run again with the same --outputs-file to finish them"
        }
    }
}

private let slackTolerance = 1e-9

public struct CleanupBenchmarkVerdictRow: Equatable, Sendable {
    /// Nil for the candidate's runs overall.
    public let category: CleanupBenchmarkCategory?
    public let runs: Int
    public let withinSlack: Int
    public let means: CleanupBenchmarkMeans
    public let passed: Bool

    public var share: Double {
        runs == 0 ? 0 : Double(withinSlack) / Double(runs)
    }

    init(category: CleanupBenchmarkCategory?, group: [CleanupBenchmarkRun], withinSlack: Int, allowance: Double) {
        self.category = category
        runs = group.count
        self.withinSlack = withinSlack
        means = CleanupBenchmarkMeans(group)
        // At least one miss is always allowed, so a small row is not failed by a
        // single run. A row with no runs has no verdict to pass.
        let allowedMisses = max(1, Int((allowance * Double(group.count) + slackTolerance).rounded(.down)))
        passed = !group.isEmpty && group.count - withinSlack <= allowedMisses
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

/// The bar: a candidate's run on a sample is within slack when, for every
/// coefficient, its slack is at most the baseline's mean slack plus the
/// coefficient's floor. A candidate passes when the runs not within slack number
/// at most the allowance's share of the row's runs, and at least one, overall and
/// in every category.
public enum CleanupBenchmarkBar {
    /// The mean slack of runs that are complete, one sample's repetitions.
    public static func slack(of runs: [CleanupBenchmarkRun]) -> CleanupBenchmarkBaselineSample {
        CleanupBenchmarkBaselineSample(
            fuzzy: meanSlack(runs.compactMap(\.scores.fuzzy)),
            embedding: meanSlack(runs.compactMap(\.scores.embedding)),
            jev: meanSlack(runs.compactMap(\.scores.jev))
        )
    }

    /// The entry for one candidate from its runs over the dataset. Every run must be
    /// complete: an empty output or a judge failure would raise a mean and loosen
    /// the bar for good.
    public static func makeEntry(
        candidateName: String,
        runs: [CleanupBenchmarkRun],
        settings: CleanupBenchmarkJudgeSettings,
        datasetSHA256: String
    ) throws -> CleanupBenchmarkBaselineEntry {
        let own = runs.filter { $0.candidateName == candidateName }
        let incomplete = own.filter { !$0.isComplete(judged: true) }.count
        guard incomplete == 0 else {
            throw CleanupBenchmarkBarError.incompleteRuns(candidate: candidateName, count: incomplete)
        }
        return CleanupBenchmarkBaselineEntry(
            judgeSHA256: try settings.judgeSHA256(),
            snapshots: Set(own.flatMap(\.scores.models)).sorted(),
            datasetSHA256: datasetSHA256,
            samples: Dictionary(uniqueKeysWithValues: Dictionary(grouping: own, by: \.sampleId).map { ($0, slack(of: $1)) })
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
            return CleanupBenchmarkVerdictRow(category: category, group: group, withinSlack: within, allowance: settings.allowance)
        }
        let categories = Set(own.map(\.sampleCategory)).sorted { $0.rawValue < $1.rawValue }
        return CleanupBenchmarkVerdict(
            candidateName: candidateName,
            baselineName: baselineName,
            rows: [row(nil, own)] + categories.map { category in row(category, own.filter { $0.sampleCategory == category }) }
        )
    }

    private static func within(_ slack: Double, _ baseline: CleanupBenchmarkSlack, floor: Double) -> Bool {
        slack <= baseline.mean + floor + slackTolerance
    }

    private static func meanSlack(_ coefficients: [Double]) -> CleanupBenchmarkSlack {
        CleanupBenchmarkSlack(mean: coefficients.map { 1 - $0 }.reduce(0, +) / Double(coefficients.count))
    }
}
