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
    public let forbiddenTerms: [String]
    public let preserveTokens: [String]
    public let requireTerminalPunctuation: Bool
    public let forbidChatResponse: Bool
    public let maxLengthRatio: Double
    public let minimumSentenceTerminators: Int?
    public let maxRunOnWords: Int?

    public init(
        requiredSubstrings: [String] = [],
        forbiddenSubstrings: [String] = [],
        forbiddenTerms: [String] = [],
        preserveTokens: [String] = [],
        requireTerminalPunctuation: Bool = true,
        forbidChatResponse: Bool = true,
        maxLengthRatio: Double = 2.5,
        minimumSentenceTerminators: Int? = nil,
        maxRunOnWords: Int? = nil
    ) {
        self.requiredSubstrings = requiredSubstrings
        self.forbiddenSubstrings = forbiddenSubstrings
        self.forbiddenTerms = forbiddenTerms
        self.preserveTokens = preserveTokens
        self.requireTerminalPunctuation = requireTerminalPunctuation
        self.forbidChatResponse = forbidChatResponse
        self.maxLengthRatio = maxLengthRatio
        self.minimumSentenceTerminators = minimumSentenceTerminators
        self.maxRunOnWords = maxRunOnWords
    }

    enum CodingKeys: String, CodingKey {
        case requiredSubstrings
        case forbiddenSubstrings
        case forbiddenTerms
        case preserveTokens
        case requireTerminalPunctuation
        case forbidChatResponse
        case maxLengthRatio
        case minimumSentenceTerminators
        case maxRunOnWords
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            requiredSubstrings: try container.decodeIfPresent([String].self, forKey: .requiredSubstrings) ?? [],
            forbiddenSubstrings: try container.decodeIfPresent([String].self, forKey: .forbiddenSubstrings) ?? [],
            forbiddenTerms: try container.decodeIfPresent([String].self, forKey: .forbiddenTerms) ?? [],
            preserveTokens: try container.decodeIfPresent([String].self, forKey: .preserveTokens) ?? [],
            requireTerminalPunctuation: try container.decodeIfPresent(Bool.self, forKey: .requireTerminalPunctuation) ?? true,
            forbidChatResponse: try container.decodeIfPresent(Bool.self, forKey: .forbidChatResponse) ?? true,
            maxLengthRatio: try container.decodeIfPresent(Double.self, forKey: .maxLengthRatio) ?? 2.5,
            minimumSentenceTerminators: try container.decodeIfPresent(Int.self, forKey: .minimumSentenceTerminators),
            maxRunOnWords: try container.decodeIfPresent(Int.self, forKey: .maxRunOnWords)
        )
    }
}

public enum CleanupBenchmarkCategory: String, Codable, Equatable, Hashable, Sendable {
    case uncategorized
    case shortSmoke = "short-smoke"
    case russianFiller = "russian-filler"
    case codeSwitching = "code-switching"
    case punctuationStructure = "punctuation-structure"
    case commandsEditor = "commands-editor"
    case inverseTextNormalization = "inverse-text-normalization"
    case safetyNegative = "safety-negative"
}

public struct CleanupBenchmarkSample: Codable, Equatable, Sendable {
    public let id: String
    public let category: CleanupBenchmarkCategory
    public let raw: String
    public let reference: String?
    public let expectation: CleanupQualityExpectation

    public init(
        id: String,
        category: CleanupBenchmarkCategory = .uncategorized,
        raw: String,
        reference: String? = nil,
        expectation: CleanupQualityExpectation
    ) {
        self.id = id
        self.category = category
        self.raw = raw
        self.reference = reference
        self.expectation = expectation
    }

    enum CodingKeys: String, CodingKey {
        case id, category, raw, reference, expectation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            category: try container.decodeIfPresent(CleanupBenchmarkCategory.self, forKey: .category) ?? .uncategorized,
            raw: try container.decode(String.self, forKey: .raw),
            reference: try container.decodeIfPresent(String.self, forKey: .reference),
            expectation: try container.decode(CleanupQualityExpectation.self, forKey: .expectation)
        )
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
