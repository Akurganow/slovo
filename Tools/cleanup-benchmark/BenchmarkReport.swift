import Foundation

public struct CleanupBenchmarkSummary: Equatable, Sendable {
    public let candidateName: String
    public let runCount: Int
    /// Runs with at least one failure code: provider error, empty output, judge error.
    public let errorCount: Int
    public let medianMilliseconds: Double
    public let p95Milliseconds: Double
    public let means: CleanupBenchmarkMeans

    /// The columns after the leading names: runs, failed runs, latency, means.
    fileprivate var columns: [String] {
        [
            "\(runCount)",
            "\(errorCount)",
            CleanupBenchmarkReportFormatter.format(medianMilliseconds),
            CleanupBenchmarkReportFormatter.format(p95Milliseconds),
            CleanupBenchmarkReportFormatter.format(means.fuzzy),
            CleanupBenchmarkReportFormatter.format(means.embedding),
            CleanupBenchmarkReportFormatter.format(means.jev),
        ]
    }
}

public struct CleanupBenchmarkCategorySummary: Equatable, Sendable {
    public let category: CleanupBenchmarkCategory
    public let summary: CleanupBenchmarkSummary
}

/// Mean coefficients over the runs that have them; nil when no run does.
public struct CleanupBenchmarkMeans: Equatable, Sendable {
    public let fuzzy: Double?
    public let embedding: Double?
    public let jev: Double?

    init(_ runs: [CleanupBenchmarkRun]) {
        func mean(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        fuzzy = mean(runs.compactMap(\.scores.fuzzy))
        embedding = mean(runs.compactMap(\.scores.embedding))
        jev = mean(runs.compactMap(\.scores.jev))
    }
}

public struct CleanupBenchmarkReport: Equatable, Sendable {
    public let runs: [CleanupBenchmarkRun]
    /// Nil when the judge did not run.
    public let judge: CleanupBenchmarkJudgeInfo?
    /// One per judged candidate; empty without a baseline.
    public let verdicts: [CleanupBenchmarkVerdict]

    public init(
        runs: [CleanupBenchmarkRun],
        judge: CleanupBenchmarkJudgeInfo? = nil,
        verdicts: [CleanupBenchmarkVerdict] = []
    ) {
        self.runs = runs
        self.judge = judge
        self.verdicts = verdicts
    }

    public var summaries: [CleanupBenchmarkSummary] {
        let names = runs.map(\.candidateName).uniqued()
        return names.map { candidateName in
            Self.summary(of: runs.filter { $0.candidateName == candidateName }, candidateName: candidateName)
        }
    }

    public var categorySummaries: [CleanupBenchmarkCategorySummary] {
        let keys = runs.map { CategorySummaryKey(candidateName: $0.candidateName, category: $0.sampleCategory) }.uniqued()
        return keys.sorted().map { key in
            let summary = Self.summary(
                of: runs.filter { $0.candidateName == key.candidateName && $0.sampleCategory == key.category },
                candidateName: key.candidateName
            )
            return CleanupBenchmarkCategorySummary(category: key.category, summary: summary)
        }
    }

    /// True when the exit code must be non-zero: a run failed, or a verdict did.
    public var failed: Bool {
        runs.contains { !$0.failures.isEmpty } || verdicts.contains { !$0.passed }
    }

    private static func summary(of candidateRuns: [CleanupBenchmarkRun], candidateName: String) -> CleanupBenchmarkSummary {
        let durations = candidateRuns
            .filter { $0.errorKind == nil }
            .map(\.durationNanoseconds)
            .sorted()
        return CleanupBenchmarkSummary(
            candidateName: candidateName,
            runCount: candidateRuns.count,
            errorCount: candidateRuns.filter { !$0.failures.isEmpty }.count,
            medianMilliseconds: percentile(durations, percentile: 0.5),
            p95Milliseconds: percentile(durations, percentile: 0.95),
            means: CleanupBenchmarkMeans(candidateRuns)
        )
    }

    private static func percentile(_ nanoseconds: [UInt64], percentile: Double) -> Double {
        guard !nanoseconds.isEmpty else { return 0 }
        let bounded = min(max(percentile, 0), 1)
        let index = Int((Double(nanoseconds.count - 1) * bounded).rounded(.up))
        return Double(nanoseconds[index]) / 1_000_000
    }
}

public enum CleanupBenchmarkReportFormatter {
    public static func render(_ report: CleanupBenchmarkReport) -> String {
        let header = "candidate,runs,failed_runs,p50_ms,p95_ms,fuzzy,embedding,jev"
        let rows = report.summaries.map { summary in
            [summary.candidateName] + summary.columns
        }
        var lines = [header] + rows.map { $0.joined(separator: ",") }
        if let judge = report.judge {
            lines.append("")
            lines.append("judge_models,judge_cost_usd")
            lines.append([
                Set(report.runs.flatMap(\.scores.models)).sorted().joined(separator: "|"),
                String(format: "%.6f", judge.costUSD),
            ].joined(separator: ","))
        }
        if !report.verdicts.isEmpty {
            lines.append("")
            lines.append(renderVerdicts(report))
        }
        return lines.joined(separator: "\n")
    }

    /// Per candidate and per category: runs, within-slack share, means, verdict.
    private static func renderVerdicts(_ report: CleanupBenchmarkReport) -> String {
        let header = "candidate,baseline,category,runs,within_slack,fuzzy,embedding,jev,verdict"
        let rows = report.verdicts.flatMap { verdict in
            verdict.rows.map { row -> String in
                [
                    verdict.candidateName,
                    verdict.baselineName,
                    row.category?.rawValue ?? "all",
                    "\(row.runs)",
                    format(Optional(row.share)),
                    format(row.means.fuzzy),
                    format(row.means.embedding),
                    format(row.means.jev),
                    row.passed ? "pass" : "fail",
                ].joined(separator: ",")
            }
        }
        return ([header] + rows).joined(separator: "\n")
    }

    public static func renderFailureBreakdown(_ report: CleanupBenchmarkReport) -> String {
        let header = "candidate,sample_index,failure,runs"
        var counts: [FailureBreakdownKey: Int] = [:]
        for run in report.runs {
            for failure in run.failures {
                let key = FailureBreakdownKey(
                    candidateName: run.candidateName,
                    sampleIndex: run.sampleIndex,
                    failure: failure
                )
                counts[key, default: 0] += 1
            }
        }

        let rows = counts.keys.sorted().map { key in
            [
                key.candidateName,
                "\(key.sampleIndex)",
                key.failure,
                "\(counts[key, default: 0])",
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    public static func renderCategoryBreakdown(_ report: CleanupBenchmarkReport) -> String {
        let header = "candidate,category,runs,failed_runs,p50_ms,p95_ms,fuzzy,embedding,jev"
        let rows = report.categorySummaries.map { summary in
            [summary.summary.candidateName, summary.category.rawValue] + summary.summary.columns
        }
        return ([header] + rows.map { $0.joined(separator: ",") }).joined(separator: "\n")
    }

    fileprivate static func format(_ value: Double?) -> String {
        value.map { String(format: "%.3f", $0) } ?? ""
    }

    fileprivate static func format(_ milliseconds: Double) -> String {
        String(format: "%.1f", milliseconds)
    }
}

private struct CategorySummaryKey: Comparable, Hashable {
    let candidateName: String
    let category: CleanupBenchmarkCategory

    static func < (lhs: CategorySummaryKey, rhs: CategorySummaryKey) -> Bool {
        if lhs.candidateName != rhs.candidateName {
            return lhs.candidateName < rhs.candidateName
        }
        return lhs.category.rawValue < rhs.category.rawValue
    }
}

private struct FailureBreakdownKey: Comparable, Hashable {
    let candidateName: String
    let sampleIndex: Int
    let failure: String

    static func < (lhs: FailureBreakdownKey, rhs: FailureBreakdownKey) -> Bool {
        if lhs.candidateName != rhs.candidateName {
            return lhs.candidateName < rhs.candidateName
        }
        if lhs.sampleIndex != rhs.sampleIndex {
            return lhs.sampleIndex < rhs.sampleIndex
        }
        return lhs.failure < rhs.failure
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
