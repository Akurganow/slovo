import Foundation

public struct CleanupBenchmarkSummary: Equatable, Sendable {
    public let candidateName: String
    public let runCount: Int
    public let passedCount: Int
    public let errorCount: Int
    public let medianMilliseconds: Double
    public let p95Milliseconds: Double

    public init(
        candidateName: String,
        runCount: Int,
        passedCount: Int,
        errorCount: Int,
        medianMilliseconds: Double,
        p95Milliseconds: Double
    ) {
        self.candidateName = candidateName
        self.runCount = runCount
        self.passedCount = passedCount
        self.errorCount = errorCount
        self.medianMilliseconds = medianMilliseconds
        self.p95Milliseconds = p95Milliseconds
    }
}

public struct CleanupBenchmarkCategorySummary: Equatable, Sendable {
    public let candidateName: String
    public let category: CleanupBenchmarkCategory
    public let runCount: Int
    public let passedCount: Int
    public let errorCount: Int
    public let medianMilliseconds: Double
    public let p95Milliseconds: Double

    public init(
        candidateName: String,
        category: CleanupBenchmarkCategory,
        runCount: Int,
        passedCount: Int,
        errorCount: Int,
        medianMilliseconds: Double,
        p95Milliseconds: Double
    ) {
        self.candidateName = candidateName
        self.category = category
        self.runCount = runCount
        self.passedCount = passedCount
        self.errorCount = errorCount
        self.medianMilliseconds = medianMilliseconds
        self.p95Milliseconds = p95Milliseconds
    }
}

public struct CleanupBenchmarkReport: Equatable, Sendable {
    public let runs: [CleanupBenchmarkRun]

    public init(runs: [CleanupBenchmarkRun]) {
        self.runs = runs
    }

    public var summaries: [CleanupBenchmarkSummary] {
        let names = runs.map(\.candidateName).uniqued()
        return names.map { candidateName in
            let candidateRuns = runs.filter { $0.candidateName == candidateName }
            let durations = candidateRuns
                .filter { $0.errorKind == nil }
                .map(\.durationNanoseconds)
                .sorted()
            return CleanupBenchmarkSummary(
                candidateName: candidateName,
                runCount: candidateRuns.count,
                passedCount: candidateRuns.filter(\.quality.passed).count,
                errorCount: candidateRuns.filter { $0.errorKind != nil }.count,
                medianMilliseconds: Self.percentile(durations, percentile: 0.5),
                p95Milliseconds: Self.percentile(durations, percentile: 0.95)
            )
        }
    }

    public var categorySummaries: [CleanupBenchmarkCategorySummary] {
        let keys = runs.map { CategorySummaryKey(candidateName: $0.candidateName, category: $0.sampleCategory) }.uniqued()
        return keys.sorted().map { key in
            let categoryRuns = runs.filter {
                $0.candidateName == key.candidateName && $0.sampleCategory == key.category
            }
            let durations = categoryRuns
                .filter { $0.errorKind == nil }
                .map(\.durationNanoseconds)
                .sorted()
            return CleanupBenchmarkCategorySummary(
                candidateName: key.candidateName,
                category: key.category,
                runCount: categoryRuns.count,
                passedCount: categoryRuns.filter(\.quality.passed).count,
                errorCount: categoryRuns.filter { $0.errorKind != nil }.count,
                medianMilliseconds: Self.percentile(durations, percentile: 0.5),
                p95Milliseconds: Self.percentile(durations, percentile: 0.95)
            )
        }
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
        let header = "candidate,runs,passed,errors,p50_ms,p95_ms"
        let rows = report.summaries.map { summary in
            [
                summary.candidateName,
                "\(summary.runCount)",
                "\(summary.passedCount)",
                "\(summary.errorCount)",
                Self.format(summary.medianMilliseconds),
                Self.format(summary.p95Milliseconds),
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    public static func renderFailureBreakdown(_ report: CleanupBenchmarkReport) -> String {
        let header = "candidate,sample_index,failure,runs"
        var sampleIndexes: [String: Int] = [:]
        for sampleId in report.runs.map(\.sampleId).uniqued() {
            sampleIndexes[sampleId] = sampleIndexes.count + 1
        }

        var counts: [FailureBreakdownKey: Int] = [:]
        for run in report.runs {
            for failure in run.quality.failures {
                let key = FailureBreakdownKey(
                    candidateName: run.candidateName,
                    sampleIndex: sampleIndexes[run.sampleId] ?? 0,
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
        let header = "candidate,category,runs,passed,errors,p50_ms,p95_ms"
        let rows = report.categorySummaries.map { summary in
            [
                summary.candidateName,
                summary.category.rawValue,
                "\(summary.runCount)",
                "\(summary.passedCount)",
                "\(summary.errorCount)",
                Self.format(summary.medianMilliseconds),
                Self.format(summary.p95Milliseconds),
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private static func format(_ milliseconds: Double) -> String {
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
