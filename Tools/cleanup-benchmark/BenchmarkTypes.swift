import Foundation
import SlovoCore

public struct TimedCleanupOutput: Equatable, Sendable {
    public let output: String
    public let durationNanoseconds: UInt64

    public init(output: String, durationNanoseconds: UInt64) {
        self.output = output
        self.durationNanoseconds = durationNanoseconds
    }
}

public struct CleanupBenchmarkTimer: Sendable {
    private let measureBody: @Sendable (@escaping @Sendable () async throws -> String) async throws -> TimedCleanupOutput

    @preconcurrency
    public init(
        measure: @escaping @Sendable (@escaping @Sendable () async throws -> String) async throws -> TimedCleanupOutput
    ) {
        measureBody = measure
    }

    @preconcurrency
    public func measure(
        _ operation: @escaping @Sendable () async throws -> String
    ) async throws -> TimedCleanupOutput {
        try await measureBody(operation)
    }

    public static let continuous = CleanupBenchmarkTimer { operation in
        let start = DispatchTime.now().uptimeNanoseconds
        let output = try await operation()
        let end = DispatchTime.now().uptimeNanoseconds
        return TimedCleanupOutput(output: output, durationNanoseconds: end - start)
    }
}

public struct CleanupQualityExpectation: Codable, Equatable, Sendable {
    public let requiredSubstrings: [String]
    public let forbiddenSubstrings: [String]
    public let requireTerminalPunctuation: Bool
    public let forbidChatResponse: Bool
    public let maxLengthRatio: Double
    public let minimumSentenceTerminators: Int?

    public init(
        requiredSubstrings: [String] = [],
        forbiddenSubstrings: [String] = [],
        requireTerminalPunctuation: Bool = true,
        forbidChatResponse: Bool = true,
        maxLengthRatio: Double = 2.5,
        minimumSentenceTerminators: Int? = nil
    ) {
        self.requiredSubstrings = requiredSubstrings
        self.forbiddenSubstrings = forbiddenSubstrings
        self.requireTerminalPunctuation = requireTerminalPunctuation
        self.forbidChatResponse = forbidChatResponse
        self.maxLengthRatio = maxLengthRatio
        self.minimumSentenceTerminators = minimumSentenceTerminators
    }
}

public struct CleanupBenchmarkSample: Codable, Equatable, Sendable {
    public let id: String
    public let raw: String
    public let expectation: CleanupQualityExpectation

    public init(id: String, raw: String, expectation: CleanupQualityExpectation) {
        self.id = id
        self.raw = raw
        self.expectation = expectation
    }
}

public struct CleanupQualityResult: Equatable, Sendable {
    public let passed: Bool
    public let failures: [String]

    public init(passed: Bool, failures: [String]) {
        self.passed = passed
        self.failures = failures
    }
}

public struct CleanupBenchmarkCandidate: Sendable {
    public let provider: String
    public let model: String
    public let cleaner: any Cleaner

    public init(provider: String, model: String, cleaner: any Cleaner) {
        self.provider = provider
        self.model = model
        self.cleaner = cleaner
    }

    public var name: String {
        "\(provider):\(model)"
    }
}
