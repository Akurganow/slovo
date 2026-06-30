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
        @Sendable ([CleanupBenchmarkCandidate], [CleanupBenchmarkSample], CleanupConfig, PersonalizationContext, Int) async -> CleanupBenchmarkReport
    private let readTextFile: @Sendable (String) throws -> String
    private let readDataFile: @Sendable (String) throws -> Data

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
            Int
        ) async -> CleanupBenchmarkReport = { candidates, samples, config, context, repetitions in
            await CleanupBenchmarkRunner().run(
                candidates: candidates,
                samples: samples,
                config: config,
                context: context,
                repetitions: repetitions
            )
        },
        readTextFile: @escaping @Sendable (String) throws -> String = {
            try String(contentsOfFile: $0, encoding: .utf8)
        },
        readDataFile: @escaping @Sendable (String) throws -> Data = {
            try Data(contentsOf: URL(fileURLWithPath: $0))
        }
    ) {
        self.makeCandidates = makeCandidates
        self.runBenchmark = runBenchmark
        self.readTextFile = readTextFile
        self.readDataFile = readDataFile
    }

    public func run(arguments: [String], environment: [String: String]) async -> CleanupBenchmarkCommandResult {
        do {
            let options = try CleanupBenchmarkCommandOptions.parse(arguments[...])
            let mergedEnvironment = try options.environment(
                processEnvironment: environment,
                readTextFile: readTextFile
            )
            let samples = try options.samples(readDataFile: readDataFile)
            let specs = try CleanupBenchmarkProviderSpec.parseList(options.providers)
            let candidates = try makeCandidates(specs, mergedEnvironment)
            let report = await runBenchmark(
                candidates,
                samples,
                CleanupConfig(model: "selected-per-candidate", writingStyle: options.style, language: .auto),
                PersonalizationContext(vocabulary: []),
                options.repetitions
            )
            var rendered = CleanupBenchmarkReportFormatter.render(report)
            if options.failureBreakdown {
                rendered += "\n\n" + CleanupBenchmarkReportFormatter.renderFailureBreakdown(report)
            }
            if options.categoryBreakdown {
                rendered += "\n\n" + CleanupBenchmarkReportFormatter.renderCategoryBreakdown(report)
            }
            let failed = report.runs.contains { !$0.quality.passed || $0.errorKind != nil }
            return CleanupBenchmarkCommandResult(exitCode: failed ? 2 : 0, stdout: rendered, stderr: "")
        } catch {
            return CleanupBenchmarkCommandResult(
                exitCode: 64,
                stdout: "",
                stderr: "error: \(error)\n\(Self.usage)"
            )
        }
    }

    public static let usage = """

    Usage:
      swift run slovo-cleanup-benchmark
        [--env-file .env]
        [--providers anthropic:MODEL,openai:MODEL,passthrough]
        [--samples samples.json]
        [--repetitions N]
        [--style casual|formal|very-casual]
        [--failure-breakdown]
        [--category-breakdown]

    Notes:
      The report prints aggregate metrics only. It does not print raw transcripts, cleaned output, or API keys.

    """
}

public struct CleanupBenchmarkCommandOptions: Equatable, Sendable {
    public var providers: String
    public var envFile: String?
    public var samplesPath: String?
    public var repetitions: Int
    public var style: WritingStyle
    public var failureBreakdown: Bool
    public var categoryBreakdown: Bool

    public init(
        providers: String = "anthropic:\(Config.defaultAnthropicModel),openai:\(Config.defaultOpenAIModel),passthrough",
        envFile: String? = nil,
        samplesPath: String? = nil,
        repetitions: Int = 1,
        style: WritingStyle = .casual,
        failureBreakdown: Bool = false,
        categoryBreakdown: Bool = false
    ) {
        self.providers = providers
        self.envFile = envFile
        self.samplesPath = samplesPath
        self.repetitions = repetitions
        self.style = style
        self.failureBreakdown = failureBreakdown
        self.categoryBreakdown = categoryBreakdown
    }

    public static func parse(_ arguments: ArraySlice<String>) throws -> CleanupBenchmarkCommandOptions {
        var options = CleanupBenchmarkCommandOptions()
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--providers":
                options.providers = try value(after: argument, from: &iterator)
            case "--env-file":
                options.envFile = try value(after: argument, from: &iterator)
            case "--samples":
                options.samplesPath = try value(after: argument, from: &iterator)
            case "--repetitions":
                let value = try value(after: argument, from: &iterator)
                guard let parsed = Int(value), parsed > 0 else {
                    throw CleanupBenchmarkCommandError.invalidValue(argument, value)
                }
                options.repetitions = parsed
            case "--style":
                let value = try value(after: argument, from: &iterator)
                guard let parsed = WritingStyle(rawValue: value) else {
                    throw CleanupBenchmarkCommandError.invalidValue(argument, value)
                }
                options.style = parsed
            case "--failure-breakdown":
                options.failureBreakdown = true
            case "--category-breakdown":
                options.categoryBreakdown = true
            case "--help", "-h":
                throw CleanupBenchmarkCommandError.helpRequested
            default:
                throw CleanupBenchmarkCommandError.unknownArgument(argument)
            }
        }
        return options
    }

    public func environment(
        processEnvironment: [String: String],
        readTextFile: (String) throws -> String
    ) throws -> [String: String] {
        var merged = processEnvironment
        if let envFile {
            for (key, value) in CleanupBenchmarkEnvFile.parse(try readTextFile(envFile)) {
                merged[key] = value
            }
        }
        return merged
    }

    public func samples(readDataFile: (String) throws -> Data) throws -> [CleanupBenchmarkSample] {
        guard let samplesPath else {
            return try CleanupBenchmarkDefaults.samples(readDataFile: readDataFile)
        }
        return try CleanupBenchmarkSampleLoader.decode(readDataFile(samplesPath))
    }

    private static func value(
        after argument: String,
        from iterator: inout ArraySlice<String>.Iterator
    ) throws -> String {
        guard let value = iterator.next() else {
            throw CleanupBenchmarkCommandError.missingValue(argument)
        }
        return value
    }
}

public enum CleanupBenchmarkCommandError: Error, CustomStringConvertible, Equatable, Sendable {
    case helpRequested
    case invalidValue(String, String)
    case missingValue(String)
    case unknownArgument(String)

    public var description: String {
        switch self {
        case .helpRequested:
            return "help requested"
        case .invalidValue(let argument, let value):
            return "invalid value for \(argument): \(value)"
        case .missingValue(let argument):
            return "missing value after \(argument)"
        case .unknownArgument(let argument):
            return "unknown argument: \(argument)"
        }
    }
}
