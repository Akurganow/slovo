import Foundation

/// What the benchmark reports while it runs: names and counts only, never a sample id, a text, a
/// reference or a key. The runner, the judge and the command emit these into a sink, and `line`
/// is the one place that words them.
public enum CleanupBenchmarkProgress: Equatable, Sendable {
    /// The calls to make are the matrix less the kept runs.
    case cleanupStarted(candidates: Int, samples: Int, repetitions: Int, kept: Int)
    case candidateStarted(candidate: String)
    case repetitionFinished(repetition: Int, total: Int, calls: Int, failed: Int)
    case candidateFinished(candidate: String, calls: Int, failed: Int)
    /// Every run of the candidate came from the outputs file, so no call is made.
    case candidateKept(candidate: String, kept: Int)
    case cleanupFinished(calls: Int, failed: Int)
    case judgeStarted(runs: Int)
    case judgeCandidateStarted(candidate: String, runs: Int)
    case judgeCandidateFinished(candidate: String, judged: Int, failed: Int)
    case judgeFinished(judged: Int, failed: Int, costUSD: Double)
    case baselineWriteStarted
    case baselineWriteFinished(written: Int, notWritten: Int)

    public var line: String {
        "progress: " + text
    }

    private var text: String {
        switch self {
        case .cleanupStarted(let candidates, let samples, let repetitions, let kept):
            "cleanup started: candidates \(candidates), samples \(samples), repetitions \(repetitions), "
                + "calls to make \(candidates * samples * repetitions - kept), runs kept from the outputs file \(kept)"
        case .candidateStarted(let candidate):
            "cleanup of \(candidate) started"
        case .repetitionFinished(let repetition, let total, let calls, let failed):
            "cleanup repetition \(repetition) of \(total) finished: calls made \(calls), failed \(failed)"
        case .candidateFinished(let candidate, let calls, let failed):
            "cleanup of \(candidate) finished: calls made \(calls), failed \(failed)"
        case .candidateKept(let candidate, let kept):
            "cleanup of \(candidate) has no call to make: runs kept from the outputs file \(kept)"
        case .cleanupFinished(let calls, let failed):
            "cleanup finished: calls made \(calls), failed \(failed)"
        case .judgeStarted(let runs):
            "judging started: runs to judge \(runs)"
        case .judgeCandidateStarted(let candidate, let runs):
            "judging of \(candidate) started: runs \(runs)"
        case .judgeCandidateFinished(let candidate, let judged, let failed):
            "judging of \(candidate) finished: runs judged \(judged), failed \(failed)"
        case .judgeFinished(let judged, let failed, let costUSD):
            "judging finished: runs judged \(judged), failed \(failed), judge cost usd \(String(format: "%.6f", costUSD))"
        case .baselineWriteStarted:
            "baseline write started"
        case .baselineWriteFinished(let written, let notWritten):
            "baseline write finished: entries written \(written), not written \(notWritten)"
        }
    }

    /// The default sink: each line goes to standard error at once. The report owns standard output.
    public static let toStandardError: @Sendable (CleanupBenchmarkProgress) -> Void = { event in
        // Best effort: a closed standard error never stops the run.
        try? FileHandle.standardError.write(contentsOf: Data((event.line + "\n").utf8))
    }
}
