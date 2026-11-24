import Foundation
import SlovoCore

public struct CleanupBenchmarkCommandOptions: Equatable, Sendable {
    public var providers: String
    public var envFile: String?
    public var samplesPath: String?
    public var repetitions: Int
    public var warmupRepetitions: Int
    public var style: WritingStyle
    public var failureBreakdown: Bool
    public var categoryBreakdown: Bool
    public var judge: Bool
    public var baselinePath: String?
    /// The candidate whose baseline entry judges a candidate that has none.
    public var baselineCandidate: String
    public var writeBaselinePath: String?
    public var outputsFilePath: String?

    public init(
        providers: String = "openrouter:\(Config.defaultOpenRouterModel),passthrough",
        envFile: String? = nil,
        samplesPath: String? = nil,
        repetitions: Int = 1,
        warmupRepetitions: Int = 0,
        style: WritingStyle = .casual,
        failureBreakdown: Bool = false,
        categoryBreakdown: Bool = false,
        judge: Bool = false,
        baselinePath: String? = nil,
        baselineCandidate: String = "openrouter:\(Config.defaultOpenRouterModel)",
        writeBaselinePath: String? = nil,
        outputsFilePath: String? = nil
    ) {
        self.providers = providers
        self.envFile = envFile
        self.samplesPath = samplesPath
        self.repetitions = repetitions
        self.warmupRepetitions = warmupRepetitions
        self.style = style
        self.failureBreakdown = failureBreakdown
        self.categoryBreakdown = categoryBreakdown
        self.judge = judge
        self.baselinePath = baselinePath
        self.baselineCandidate = baselineCandidate
        self.writeBaselinePath = writeBaselinePath
        self.outputsFilePath = outputsFilePath
    }

    public static func parse(_ arguments: ArraySlice<String>) throws -> CleanupBenchmarkCommandOptions {
        var options = CleanupBenchmarkCommandOptions()
        var iterator = arguments.makeIterator()
        var baselineCandidateGiven = false
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
            case "--warmup-repetitions":
                let value = try value(after: argument, from: &iterator)
                guard let parsed = Int(value), parsed >= 0 else {
                    throw CleanupBenchmarkCommandError.invalidValue(argument, value)
                }
                options.warmupRepetitions = parsed
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
            case "--judge":
                options.judge = true
            case "--baseline":
                options.baselinePath = try value(after: argument, from: &iterator)
            case "--baseline-candidate":
                options.baselineCandidate = try value(after: argument, from: &iterator)
                baselineCandidateGiven = true
            case "--write-baseline":
                options.writeBaselinePath = try value(after: argument, from: &iterator)
            case "--outputs-file":
                options.outputsFilePath = try value(after: argument, from: &iterator)
            case "--help", "-h":
                throw CleanupBenchmarkCommandError.helpRequested
            default:
                throw CleanupBenchmarkCommandError.unknownArgument(argument)
            }
        }
        try options.validate(baselineCandidateGiven: baselineCandidateGiven)
        return options
    }

    private func validate(baselineCandidateGiven: Bool) throws {
        if !judge {
            for (flag, given) in [("--baseline", baselinePath != nil), ("--write-baseline", writeBaselinePath != nil)]
            where given {
                throw CleanupBenchmarkCommandError.requires(flag, "--judge")
            }
        }
        if baselineCandidateGiven, baselinePath == nil {
            throw CleanupBenchmarkCommandError.requires("--baseline-candidate", "--baseline")
        }
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

    public func samplesData(readDataFile: (String) throws -> Data) throws -> Data {
        try readDataFile(samplesPath ?? CleanupBenchmarkDefaults.defaultSamplesPath)
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
    case requires(String, String)
    case noBaselineEntry(String, String)
    case baselineDatasetMismatch(String)

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
        case .requires(let flag, let other):
            return "\(flag) requires \(other)"
        case .noBaselineEntry(let candidate, let fallback):
            return "baseline has no entry for \(candidate) or for the fallback \(fallback)"
        case .baselineDatasetMismatch(let entry):
            return "baseline entry \(entry) was recorded on a different dataset file"
        }
    }
}
