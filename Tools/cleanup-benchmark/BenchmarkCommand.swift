import CryptoKit
import Foundation
import SlovoCore

public struct CleanupBenchmarkCommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct CleanupBenchmarkCommandDriver: Sendable {
    private let makeCandidates:
        @Sendable ([CleanupBenchmarkProviderSpec], [String: String]) throws -> [CleanupBenchmarkCandidate]
    private let runBenchmark:
        @Sendable (
            [CleanupBenchmarkCandidate],
            [CleanupBenchmarkSample],
            CleanupConfig,
            PersonalizationContext,
            Int,
            Int
        ) async -> CleanupBenchmarkReport
    private let makeTransport: @Sendable ([String: String]) throws -> any CleanupBenchmarkTransport
    private let readTextFile: @Sendable (String) throws -> String
    private let readDataFile: @Sendable (String) throws -> Data
    private let writeDataFile: @Sendable (String, Data) throws -> Void

    @preconcurrency
    public init(
        makeCandidates: @escaping @Sendable ([CleanupBenchmarkProviderSpec], [String: String]) throws -> [CleanupBenchmarkCandidate] = { specs, environment in
            try specs.map { spec in
                try CleanupBenchmarkCandidateFactory.makeCandidate(for: spec, environment: environment)
            }
        },
        runBenchmark: @escaping @Sendable (
            [CleanupBenchmarkCandidate],
            [CleanupBenchmarkSample],
            CleanupConfig,
            PersonalizationContext,
            Int,
            Int
        ) async -> CleanupBenchmarkReport = { candidates, samples, config, context, repetitions, warmupRepetitions in
            await CleanupBenchmarkRunner().run(
                candidates: candidates,
                samples: samples,
                config: config,
                context: context,
                repetitions: repetitions,
                warmupRepetitions: warmupRepetitions
            )
        },
        makeTransport: @escaping @Sendable ([String: String]) throws -> any CleanupBenchmarkTransport = { environment in
            CleanupBenchmarkOpenRouterTransport(
                apiKey: try CleanupBenchmarkCandidateFactory.key("OPENROUTER_API_KEY", in: environment)
            )
        },
        readTextFile: @escaping @Sendable (String) throws -> String = {
            try String(contentsOfFile: $0, encoding: .utf8)
        },
        readDataFile: @escaping @Sendable (String) throws -> Data = {
            try Data(contentsOf: URL(fileURLWithPath: $0))
        },
        writeDataFile: @escaping @Sendable (String, Data) throws -> Void = {
            try $1.write(to: URL(fileURLWithPath: $0), options: .atomic)
        }
    ) {
        self.makeCandidates = makeCandidates
        self.runBenchmark = runBenchmark
        self.makeTransport = makeTransport
        self.readTextFile = readTextFile
        self.readDataFile = readDataFile
        self.writeDataFile = writeDataFile
    }

    /// Exit codes: 0 when nothing failed; 2 when a run failed (provider error, empty
    /// output, judge error) or a verdict is `fail`; 64 when the arguments or files
    /// are unusable, before any request is sent.
    public func run(arguments: [String], environment: [String: String]) async -> CleanupBenchmarkCommandResult {
        let setup: Setup
        do {
            setup = try prepare(arguments: arguments, environment: environment)
        } catch {
            return CleanupBenchmarkCommandResult(
                exitCode: 64,
                stdout: "",
                stderr: "error: \(error)\n\(Self.usage)"
            )
        }
        let benchmark = await runBenchmark(
            setup.candidates,
            setup.samples,
            CleanupConfig(model: "selected-per-candidate", writingStyle: setup.options.style),
            PersonalizationContext(vocabulary: []),
            setup.options.repetitions,
            setup.options.warmupRepetitions
        )
        let (report, errors) = await finish(benchmark, setup: setup)
        let stderr = errors.map { "error: \($0)\n" }.joined()
        var rendered = CleanupBenchmarkReportFormatter.render(report)
        if setup.options.failureBreakdown {
            rendered += "\n\n" + CleanupBenchmarkReportFormatter.renderFailureBreakdown(report)
        }
        if setup.options.categoryBreakdown {
            rendered += "\n\n" + CleanupBenchmarkReportFormatter.renderCategoryBreakdown(report)
        }
        return CleanupBenchmarkCommandResult(
            exitCode: report.failed || !stderr.isEmpty ? 2 : 0,
            stdout: rendered,
            stderr: stderr
        )
    }

    private struct Setup {
        let options: CleanupBenchmarkCommandOptions
        let samples: [CleanupBenchmarkSample]
        let datasetSHA256: String
        let candidates: [CleanupBenchmarkCandidate]
        let judge: (judge: CleanupBenchmarkJudge, settings: CleanupBenchmarkJudgeSettings)?
        let baseline: CleanupBenchmarkBaselineFile?
        let baselineCandidate: String
        let existingBaseline: CleanupBenchmarkBaselineFile?
    }

    /// Everything that can be wrong before a paid request goes out.
    private func prepare(arguments: [String], environment: [String: String]) throws -> Setup {
        let options = try CleanupBenchmarkCommandOptions.parse(arguments[...])
        let mergedEnvironment = try options.environment(processEnvironment: environment, readTextFile: readTextFile)
        let data = try options.samplesData(readDataFile: readDataFile)
        let samples = try CleanupBenchmarkSampleLoader.decode(data)
        let specs = try CleanupBenchmarkProviderSpec.parseList(options.providers)
        let candidates = try makeCandidates(specs, mergedEnvironment)

        var judge: (judge: CleanupBenchmarkJudge, settings: CleanupBenchmarkJudgeSettings)?
        if options.judge {
            let settings = try CleanupBenchmarkJudgeSettings.decode(
                try readDataFile(CleanupBenchmarkJudgeSettings.defaultPath)
            )
            let client = CleanupBenchmarkJudgeClient(transport: try makeTransport(mergedEnvironment), settings: settings)
            judge = (CleanupBenchmarkJudge(client: client, settings: settings), settings)
        }

        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var baseline: CleanupBenchmarkBaselineFile?
        if let path = options.baselinePath {
            let file = try CleanupBenchmarkBaselineFile.decode(try readDataFile(path))
            for candidate in candidates {
                guard let found = file.entry(for: candidate.name, fallback: options.baselineCandidate) else {
                    throw CleanupBenchmarkCommandError.noBaselineEntry(candidate.name, options.baselineCandidate)
                }
                guard found.entry.datasetSHA256 == digest else {
                    throw CleanupBenchmarkCommandError.baselineDatasetMismatch(found.name)
                }
            }
            baseline = file
        }

        var existing: CleanupBenchmarkBaselineFile?
        if let path = options.writeBaselinePath {
            do {
                existing = try CleanupBenchmarkBaselineFile.decode(try readDataFile(path))
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                existing = CleanupBenchmarkBaselineFile()
            }
        }
        return Setup(
            options: options,
            samples: samples,
            datasetSHA256: digest,
            candidates: candidates,
            judge: judge,
            baseline: baseline,
            baselineCandidate: options.baselineCandidate,
            existingBaseline: existing
        )
    }

    /// Judges the runs, then settles the verdicts and writes the opt-in files. A failed
    /// write is reported next to the report it belongs to, so a paid run is never lost.
    private func finish(
        _ report: CleanupBenchmarkReport,
        setup: Setup
    ) async -> (report: CleanupBenchmarkReport, errors: [String]) {
        var report = report
        var errors: [String] = []
        var settings: CleanupBenchmarkJudgeSettings?
        if let judge = setup.judge {
            let scored = await judge.judge.score(report.runs, samples: setup.samples)
            report = CleanupBenchmarkReport(runs: scored.runs, judge: scored.info)
            settings = judge.settings
        }
        if let path = setup.options.outputsFilePath {
            do {
                try writeDataFile(path, try CleanupBenchmarkOutputsFile.encode(report.runs))
            } catch {
                errors.append("outputs file not written: \(error)")
            }
        }
        guard let settings else { return (report, errors) }
        if let baseline = setup.baseline {
            report = CleanupBenchmarkReport(
                runs: report.runs,
                judge: report.judge,
                verdicts: setup.candidates.compactMap { candidate in
                    baseline.entry(for: candidate.name, fallback: setup.baselineCandidate).map { found in
                        CleanupBenchmarkBar.verdict(
                            candidateName: candidate.name,
                            baselineName: found.name,
                            runs: report.runs,
                            entry: found.entry,
                            settings: settings.bar
                        )
                    }
                }
            )
        }
        if let path = setup.options.writeBaselinePath, let existing = setup.existingBaseline {
            do {
                var entries: [String: CleanupBenchmarkBaselineEntry] = [:]
                for candidate in setup.candidates {
                    entries[candidate.name] = try CleanupBenchmarkBar.makeEntry(
                        candidateName: candidate.name,
                        runs: report.runs,
                        settings: settings,
                        info: report.judge ?? CleanupBenchmarkJudgeInfo(),
                        datasetSHA256: setup.datasetSHA256
                    )
                }
                try writeDataFile(path, try existing.merging(entries).encoded())
            } catch {
                errors.append("baseline not written: \(error)")
            }
        }
        return (report, errors)
    }

    public static let usage = """

    Usage:
      swift run slovo-cleanup-benchmark
        [--env-file .env]
        [--providers catalog|openrouter:MODEL,passthrough]
        [--samples samples.json]
        [--repetitions N]
        [--warmup-repetitions N]
        [--style casual|formal|very-casual]
        [--judge]
        [--baseline Benchmarks/cleanup/baseline.json]
        [--baseline-candidate PROVIDER:MODEL]
        [--write-baseline Benchmarks/cleanup/baseline.json]
        [--outputs-file outputs.jsonl]
        [--failure-breakdown]
        [--category-breakdown]

    Notes:
      The report prints aggregate metrics only. It does not print raw transcripts, cleaned output, or API keys.
      The passthrough candidate is the raw-mode (cleanup disabled) baseline: a no-op cleaner timed in place of the whole cleaner stage raw mode skips.
      Without --judge only the fuzzy coefficient is computed, no request leaves the Mac except the candidates' own, and no verdict is issued.
      --judge sends each sample's raw text, reference and the candidate's output to OpenRouter (Jev decisions and embeddings) and needs OPENROUTER_API_KEY.
      --baseline applies the bar: each candidate is judged against its own entry, or against the entry named by
      --baseline-candidate (default: openrouter:\(Config.defaultOpenRouterModel)) when it has none.
      --write-baseline writes the entries of the candidates that ran and leaves all other entries as they are.
      --outputs-file writes one JSON line per run, with the candidates' output text. It is opt-in and local.
      Exit code: 0 when no run failed and every verdict passed (or none was asked for);
      2 when a run failed (provider error, empty output, judge error) or a candidate failed the bar;
      64 when the arguments or files are unusable. The key comes from the environment or --env-file; nothing is asked interactively.

    """
}
