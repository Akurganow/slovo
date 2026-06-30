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

    private static func format(_ milliseconds: Double) -> String {
        String(format: "%.1f", milliseconds)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
