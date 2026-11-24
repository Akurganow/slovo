import Dispatch
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

public enum CleanupBenchmarkCategory: String, Codable, Equatable, Hashable, Sendable {
    case uncategorized
    case shortSmoke = "short-smoke"
    case russianFiller = "russian-filler"
    case codeSwitching = "code-switching"
    case punctuationStructure = "punctuation-structure"
    case commandsEditor = "commands-editor"
    case inverseTextNormalization = "inverse-text-normalization"
    case safetyNegative = "safety-negative"
    case instructionShaped = "instruction-shaped-transcript"
}

/// One dictation and the cleanup it should produce. The reference is the
/// expected result every output is scored against, never the dirty `raw` text.
public struct CleanupBenchmarkSample: Codable, Equatable, Sendable {
    public let id: String
    public let category: CleanupBenchmarkCategory
    public let raw: String
    public let reference: String

    public init(
        id: String,
        category: CleanupBenchmarkCategory = .uncategorized,
        raw: String,
        reference: String
    ) {
        self.id = id
        self.category = category
        self.raw = raw
        self.reference = reference
    }

    enum CodingKeys: String, CodingKey {
        case id, category, raw, reference
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            category: try container.decodeIfPresent(CleanupBenchmarkCategory.self, forKey: .category) ?? .uncategorized,
            raw: try container.decode(String.self, forKey: .raw),
            reference: try container.decode(String.self, forKey: .reference)
        )
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
