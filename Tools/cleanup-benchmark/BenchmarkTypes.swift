import Dispatch
import SlovoCore

/// What one cleaning call returned: the text, and what the provider charged for it.
public struct CleanupBenchmarkCleaned: Equatable, Sendable {
    public let text: String
    /// Nil when the provider named no cost.
    public let costUSD: Double?

    public init(text: String, costUSD: Double? = nil) {
        self.text = text
        self.costUSD = costUSD
    }
}

public struct TimedCleanupOutput: Equatable, Sendable {
    public let output: String
    public let costUSD: Double?
    public let durationNanoseconds: UInt64

    public init(output: String, costUSD: Double? = nil, durationNanoseconds: UInt64) {
        self.output = output
        self.costUSD = costUSD
        self.durationNanoseconds = durationNanoseconds
    }
}

public struct CleanupBenchmarkTimer: Sendable {
    private let measureBody: @Sendable (@escaping @Sendable () async throws -> CleanupBenchmarkCleaned) async throws -> TimedCleanupOutput

    @preconcurrency
    public init(
        measure: @escaping @Sendable (@escaping @Sendable () async throws -> CleanupBenchmarkCleaned) async throws -> TimedCleanupOutput
    ) {
        measureBody = measure
    }

    @preconcurrency
    public func measure(
        _ operation: @escaping @Sendable () async throws -> CleanupBenchmarkCleaned
    ) async throws -> TimedCleanupOutput {
        try await measureBody(operation)
    }

    public static let continuous = CleanupBenchmarkTimer { operation in
        let start = DispatchTime.now().uptimeNanoseconds
        let cleaned = try await operation()
        let end = DispatchTime.now().uptimeNanoseconds
        return TimedCleanupOutput(output: cleaned.text, costUSD: cleaned.costUSD, durationNanoseconds: end - start)
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

/// One dictation and the cleanup it should produce. The references are what every output
/// is scored against, never the dirty `raw` text. The first is the expected result; the
/// others are equally valid forms of it (the other script of an English term).
public struct CleanupBenchmarkSample: Codable, Equatable, Sendable {
    public let id: String
    public let category: CleanupBenchmarkCategory
    public let raw: String
    public let references: [String]

    /// The first reference.
    public var expected: String {
        references[0]
    }

    public init(
        id: String,
        category: CleanupBenchmarkCategory = .uncategorized,
        raw: String,
        references: [String]
    ) {
        self.id = id
        self.category = category
        self.raw = raw
        self.references = references
    }

    enum CodingKeys: String, CodingKey {
        case id, category, raw, references
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let references = try container.decode([String].self, forKey: .references)
        guard !references.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .references, in: container, debugDescription: "a sample needs a reference")
        }
        self.init(
            id: try container.decode(String.self, forKey: .id),
            category: try container.decodeIfPresent(CleanupBenchmarkCategory.self, forKey: .category) ?? .uncategorized,
            raw: try container.decode(String.self, forKey: .raw),
            references: references
        )
    }
}

public struct CleanupBenchmarkCandidate: Sendable {
    public let provider: String
    public let model: String
    public let clean: @Sendable (String, CleanupConfig, PersonalizationContext) async throws -> CleanupBenchmarkCleaned

    @preconcurrency
    public init(
        provider: String,
        model: String,
        clean: @escaping @Sendable (String, CleanupConfig, PersonalizationContext) async throws -> CleanupBenchmarkCleaned
    ) {
        self.provider = provider
        self.model = model
        self.clean = clean
    }

    /// A candidate whose provider reports no cost.
    public init(provider: String, model: String, cleaner: any Cleaner) {
        self.init(provider: provider, model: model) { raw, config, context in
            CleanupBenchmarkCleaned(text: try await cleaner.clean(raw, config: config, context: context))
        }
    }

    public var name: String {
        "\(provider):\(model)"
    }
}
