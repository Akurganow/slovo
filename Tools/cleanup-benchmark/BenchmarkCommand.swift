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

/// Everything the benchmark runner needs for one run, including what an earlier
/// process already finished.
public struct CleanupBenchmarkRunPlan: Sendable {
    public let candidates: [CleanupBenchmarkCandidate]
    public let samples: [CleanupBenchmarkSample]
    public let config: CleanupConfig
    public let context: PersonalizationContext
    public let repetitions: Int
    public let warmupRepetitions: Int
    public let previous: [CleanupBenchmarkRunKey: CleanupBenchmarkRun]
    public let record: @Sendable (CleanupBenchmarkRun) -> Void
}

public struct CleanupBenchmarkCommandDriver: Sendable {
    private let makeCandidates:
        @Sendable ([CleanupBenchmarkProviderSpec], [String: String]) throws -> [CleanupBenchmarkCandidate]
    private let runBenchmark: @Sendable (CleanupBenchmarkRunPlan) async -> CleanupBenchmarkReport
    private let makeTransport: @Sendable ([String: String]) throws -> any CleanupBenchmarkTransport
    private let readTextFile: @Sendable (String) throws -> String
    private let readDataFile: @Sendable (String) throws -> Data
    private let writeDataFile: @Sendable (String, Data) throws -> Void
    private let appendDataFile: @Sendable (String, Data) throws -> Void

    @preconcurrency
    public init(
        makeCandidates: @escaping @Sendable ([CleanupBenchmarkProviderSpec], [String: String]) throws -> [CleanupBenchmarkCandidate] = { specs, environment in
            try specs.map { spec in
                try CleanupBenchmarkCandidateFactory.makeCandidate(for: spec, environment: environment)
            }
        },
        runBenchmark: @escaping @Sendable (CleanupBenchmarkRunPlan) async -> CleanupBenchmarkReport = { plan in
            await CleanupBenchmarkRunner().run(
                candidates: plan.candidates,
                samples: plan.samples,
                config: plan.config,
                context: plan.context,
                repetitions: plan.repetitions,
                warmupRepetitions: plan.warmupRepetitions,
                previous: plan.previous,
                record: plan.record
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
        },
        appendDataFile: @escaping @Sendable (String, Data) throws -> Void = CleanupBenchmarkCommandDriver.appendDataFile
    ) {
        self.makeCandidates = makeCandidates
        self.runBenchmark = runBenchmark
        self.makeTransport = makeTransport
        self.readTextFile = readTextFile
        self.readDataFile = readDataFile
        self.writeDataFile = writeDataFile
        self.appendDataFile = appendDataFile
    }

    /// Exit codes: see `usage`.
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
        let benchmark = await runBenchmark(CleanupBenchmarkRunPlan(
            candidates: setup.candidates,
            samples: setup.samples,
            config: CleanupConfig(model: "selected-per-candidate", writingStyle: setup.options.style),
            context: PersonalizationContext(vocabulary: []),
            repetitions: setup.repetitions,
            warmupRepetitions: setup.options.warmupRepetitions,
            previous: setup.previous,
            record: { setup.recorder?.record($0) }
        ))
        let (report, errors) = await finish(benchmark, setup: setup)
        var rendered = CleanupBenchmarkReportFormatter.render(report)
        if setup.options.failureBreakdown {
            rendered += "\n\n" + CleanupBenchmarkReportFormatter.renderFailureBreakdown(report)
        }
        if setup.options.categoryBreakdown {
            rendered += "\n\n" + CleanupBenchmarkReportFormatter.renderCategoryBreakdown(report)
        }
        return CleanupBenchmarkCommandResult(
            exitCode: report.failed || !errors.isEmpty ? 2 : 0,
            stdout: rendered,
            stderr: errors.map { "error: \($0)\n" }.joined()
        )
    }

    private struct Setup {
        let options: CleanupBenchmarkCommandOptions
        /// What `--repetitions` was, or the default for the run.
        let repetitions: Int
        let samples: [CleanupBenchmarkSample]
        let datasetSHA256: String
        let candidates: [CleanupBenchmarkCandidate]
        let judge: CleanupBenchmarkJudge?
        /// Each candidate's baseline entry, own or fallback; empty without `--baseline`.
        let entries: [String: (name: String, entry: CleanupBenchmarkBaselineEntry)]
        let existingBaseline: CleanupBenchmarkBaselineFile?
        /// What the outputs file says earlier processes finished.
        let previous: [CleanupBenchmarkRunKey: CleanupBenchmarkRun]
        let recorder: CleanupBenchmarkOutputsRecorder?
    }

    /// Appends to the file, first ending a line that a killed process left without its
    /// newline, so the next line is not joined to it and lost.
    public static func appendDataFile(_ path: String, _ data: Data) throws {
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        let handle = try FileHandle(forUpdating: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        var bytes = data
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            if try handle.read(upToCount: 1) != Data("\n".utf8) {
                bytes = Data("\n".utf8) + data
            }
        }
        try handle.write(contentsOf: bytes)
    }

    private func decodeBaseline(_ path: String) throws -> CleanupBenchmarkBaselineFile {
        let data = try readDataFile(path)
        do {
            return try CleanupBenchmarkBaselineFile.decode(data)
        } catch is DecodingError {
            throw CleanupBenchmarkCommandError.baselineUnreadable(path)
        }
    }

    /// Everything that can be wrong before a paid request goes out.
    private func prepare(arguments: [String], environment: [String: String]) throws -> Setup {
        let options = try CleanupBenchmarkCommandOptions.parse(arguments[...])
        let mergedEnvironment = try options.environment(processEnvironment: environment, readTextFile: readTextFile)
        let data = try options.samplesData(readDataFile: readDataFile)
        let samples = try CleanupBenchmarkSampleLoader.decode(data)
        let specs = try CleanupBenchmarkProviderSpec.parseList(options.providers)
        let candidates = try makeCandidates(specs, mergedEnvironment)

        var judge: CleanupBenchmarkJudge?
        var repetitions = options.repetitions ?? 1
        if options.judge {
            let settings = try CleanupBenchmarkJudgeSettings.decode(
                try readDataFile(CleanupBenchmarkJudgeSettings.defaultPath)
            )
            if options.baselinePath != nil || options.writeBaselinePath != nil {
                repetitions = options.repetitions ?? settings.bar.repetitions
                guard repetitions == settings.bar.repetitions else {
                    throw CleanupBenchmarkCommandError.repetitionsMismatch(given: repetitions, required: settings.bar.repetitions)
                }
            }
            judge = CleanupBenchmarkJudge(transport: try makeTransport(mergedEnvironment), settings: settings)
        }

        let digest = CleanupBenchmarkDigest.sha256(data)
        var entries: [String: (name: String, entry: CleanupBenchmarkBaselineEntry)] = [:]
        if let path = options.baselinePath, let judge {
            let file = try decodeBaseline(path)
            for candidate in candidates {
                guard let found = file.entry(for: candidate.name, fallback: options.baselineCandidate) else {
                    throw CleanupBenchmarkCommandError.noBaselineEntry(candidate.name, options.baselineCandidate)
                }
                guard found.entry.datasetSHA256 == digest else {
                    throw CleanupBenchmarkCommandError.baselineDatasetMismatch(found.name)
                }
                guard found.entry.judgeSHA256 == (try judge.settings.judgeSHA256()) else {
                    throw CleanupBenchmarkCommandError.baselineJudgeMismatch(found.name)
                }
                let bar = judge.settings.bar
                guard found.entry.repetitions == bar.repetitions, found.entry.dropWorst == bar.dropWorst else {
                    throw CleanupBenchmarkCommandError.baselineSchemeMismatch(found.name)
                }
                guard found.entry.style == options.style else {
                    throw CleanupBenchmarkCommandError.baselineStyleMismatch(entry: found.name, style: found.entry.style.rawValue)
                }
                entries[candidate.name] = found
            }
        }

        var existing: CleanupBenchmarkBaselineFile?
        if let path = options.writeBaselinePath {
            do {
                existing = try decodeBaseline(path)
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                existing = CleanupBenchmarkBaselineFile()
            }
        }

        var previous: [CleanupBenchmarkRunKey: CleanupBenchmarkRun] = [:]
        var recorder: CleanupBenchmarkOutputsRecorder?
        if let path = options.outputsFilePath {
            let binding = CleanupBenchmarkOutputsBinding(
                samples: samples, judgeSHA256: try judge?.settings.judgeSHA256(), style: options.style
            )
            do {
                previous = try CleanupBenchmarkOutputsFile.resume(from: try readDataFile(path), samples: samples, binding: binding)
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                previous = [:]
            }
            recorder = CleanupBenchmarkOutputsRecorder(binding: binding) { try appendDataFile(path, $0) }
        }
        return Setup(
            options: options,
            repetitions: repetitions,
            samples: samples,
            datasetSHA256: digest,
            candidates: candidates,
            judge: judge,
            entries: entries,
            existingBaseline: existing,
            previous: previous,
            recorder: recorder
        )
    }

    /// Judges the runs that are not yet judged, settles the verdicts and writes the
    /// baseline. A failure is reported next to the report it belongs to, so a paid
    /// run is never lost.
    private func finish(
        _ report: CleanupBenchmarkReport,
        setup: Setup
    ) async -> (report: CleanupBenchmarkReport, errors: [String]) {
        var report = report
        var errors: [String] = []
        if let judge = setup.judge {
            // An empty output stays a recorded failure of the candidate: the judge never sees it.
            let pending = report.runs.indices.filter { !report.runs[$0].isComplete(judged: true) && !report.runs[$0].hasEmptyOutput }
            let scored = await judge.score(pending.map { report.runs[$0] }, samples: setup.samples) { setup.recorder?.record($0) }
            var runs = report.runs
            for (index, run) in zip(pending, scored.runs) {
                runs[index] = run
            }
            errors += scored.info.embeddingErrors.map { "embeddings request failed: \($0)" }
            report = CleanupBenchmarkReport(
                runs: runs,
                judge: scored.info,
                verdicts: setup.candidates.compactMap { candidate in
                    setup.entries[candidate.name].map { found in
                        CleanupBenchmarkBar.verdict(
                            candidateName: candidate.name,
                            baselineName: found.name,
                            runs: runs,
                            entry: found.entry,
                            settings: judge.settings.bar
                        )
                    }
                }
            )
            errors += writeBaseline(report, judge: judge, setup: setup)
        }
        errors += setup.recorder?.error.map { [$0] } ?? []
        return (report, errors)
    }

    /// Writes an entry for each candidate whose runs are all complete; the others
    /// are named in the errors and leave their old entries as they were.
    private func writeBaseline(_ report: CleanupBenchmarkReport, judge: CleanupBenchmarkJudge, setup: Setup) -> [String] {
        guard let path = setup.options.writeBaselinePath, let existing = setup.existingBaseline else { return [] }
        var errors: [String] = []
        var entries: [String: CleanupBenchmarkBaselineEntry] = [:]
        for candidate in setup.candidates {
            do {
                entries[candidate.name] = try CleanupBenchmarkBar.makeEntry(
                    candidateName: candidate.name,
                    runs: report.runs,
                    settings: judge.settings,
                    datasetSHA256: setup.datasetSHA256,
                    style: setup.options.style
                )
            } catch {
                var message = "\(error)"
                if case .incompleteRuns = error as? CleanupBenchmarkBarError, setup.options.outputsFilePath != nil {
                    message += "; run again with the same --outputs-file to finish them"
                }
                errors.append(message)
            }
        }
        guard !entries.isEmpty else { return errors }
        do {
            try writeDataFile(path, try existing.merging(entries).encoded())
        } catch {
            errors.append("baseline not written: \(error)")
        }
        return errors
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
      --judge sends each sample's raw text, references and the candidate's output to OpenRouter (Jev decisions and embeddings) and needs OPENROUTER_API_KEY.
      --baseline and --write-baseline use bar.repetitions in judge.json as --repetitions (another explicit value is refused):
      one scheme measures entry and candidate.
      --baseline applies the bar: each candidate is judged against its own entry, or against the entry named by
      --baseline-candidate (default: openrouter:\(Config.defaultOpenRouterModel)) when it has none.
      A judged run uses --providers catalog or a named model: passthrough is judged like any candidate; it fails against another model's
      entry, and --write-baseline gives it an entry of its own when it is in --providers.
      --write-baseline writes an entry for each candidate whose runs are all complete (an output, no failure, three
      coefficients) and leaves every other entry as it is. A candidate with incomplete runs gets no entry; stderr says how many.
      --outputs-file is append-only JSON Lines, local, with the candidates' output text. A line is added when a run's cleanup
      finishes and again when it is judged. Naming an existing file resumes it: complete runs are not repeated, a run with an
      output but no full score is judged again, a provider error is run again, an empty output is neither. A file written for other
      sample ids or raws, under another cleanup prompt or by another --style, is refused; a run scored under other judge settings
      keeps its output and is judged again, and one whose references changed but not the first keeps its Jev score and is only
      embedded again.
      Exit code: 0 when no run failed and every verdict passed (or none was asked for);
      2 when a run failed (a failure code in --failure-breakdown), a candidate failed the bar, or a file could not be written;
      64 when the arguments or files are unusable, before any request is sent.
      The key comes from the environment or --env-file; nothing is asked interactively.

    """
}
