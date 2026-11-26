import Testing

import CleanupBenchmark

@Suite("Cleanup benchmark failure breakdown")
struct CleanupBenchmarkFailureBreakdownTests {
    /// Stated sensitivity: failure diagnostics that print raw text, cleaned text,
    /// or caller-provided sample ids can leak benchmark payloads while trying to
    /// explain quality failures.
    @Test
    func failureBreakdownShowsCodesWithoutPayloadText() {
        let report = CleanupBenchmarkReport(runs: [
            CleanupBenchmarkRun(
                sampleId: "sample-secret",
                candidateName: "openai:gpt-test",
                durationNanoseconds: 12_000_000,
                output: "OUTPUT-SECRET",
                failures: ["empty-output", "jev-refusal"],
                errorKind: nil
            ),
            CleanupBenchmarkRun(
                sampleId: "sample-secret",
                candidateName: "openai:gpt-test",
                durationNanoseconds: 13_000_000,
                failures: ["empty-output"],
                errorKind: nil
            ),
        ])

        let rendered = CleanupBenchmarkReportFormatter.renderFailureBreakdown(report)

        #expect(rendered.contains("candidate,sample_index,failure,runs"))
        #expect(rendered.contains("openai:gpt-test,1,empty-output,2"))
        #expect(rendered.contains("openai:gpt-test,1,jev-refusal,1"))
        #expect(!rendered.contains("sample-secret"))
        #expect(!rendered.contains("OUTPUT-SECRET"))
        #expect(!rendered.contains("raw"))
        #expect(!rendered.contains("cleaned"))
    }

    /// Stated sensitivity: keeping the breakdown formatter disconnected from
    /// the executable leaves live provider failures opaque in real benchmark
    /// runs.
    @Test
    func commandDriverCanAppendFailureBreakdown() async {
        let driver = CleanupBenchmarkCommandDriver(runBenchmark: { plan in
            CleanupBenchmarkReport(runs: [
                CleanupBenchmarkRun(
                    sampleId: "sample-secret",
                    candidateName: plan.candidates[0].name,
                    durationNanoseconds: 12_000_000,
                    failures: ["jev-refusal"],
                    errorKind: nil
                ),
            ])
        })

        let result = await driver.run(
            arguments: ["--providers", "passthrough", "--failure-breakdown", "--category-breakdown"],
            environment: [:]
        )

        #expect(result.exitCode == 2)
        #expect(result.stdout.contains("candidate,runs,failed_runs,p50_ms,p95_ms,max_ms,fuzzy,embedding,jev"))
        #expect(result.stdout.contains("candidate,sample_index,failure,runs"))
        #expect(result.stdout.contains("passthrough:none,1,jev-refusal,1"))
        #expect(result.stdout.contains("candidate,category,runs,failed_runs,p50_ms,p95_ms,max_ms,fuzzy,embedding,jev"))
        #expect(result.stdout.contains("passthrough:none,uncategorized,1,1,12.0,12.0,12.0,,,"))
        #expect(!result.stdout.contains("sample-secret"))
    }
}
