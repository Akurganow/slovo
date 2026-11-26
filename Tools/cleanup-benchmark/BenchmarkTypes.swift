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
    case languages
    case mixedLanguages = "mixed-languages"
    case translation
}

/// The language a translation sample is cleaned into: its catalogue code and the name the
/// translate prompt and the judge use.
public struct CleanupBenchmarkTranslationTarget: Equatable, Sendable {
    public let code: String
    public let name: String

    /// Nil for a code the catalogue does not offer.
    public init?(code: String) {
        guard RecognitionLanguageCatalog.isSupported(code), let name = RecognitionLanguageCatalog.displayName(for: code) else {
            return nil
        }
        self.code = code
        self.name = name
    }
}

/// One dictation and the cleanup it should produce. The references are what every output
/// is scored against, never the dirty `raw` text. The first is the expected result; the
/// others are equally valid forms of it (the other script of an English term).
public struct CleanupBenchmarkSample: Decodable, Equatable, Sendable {
    public let id: String
    public let category: CleanupBenchmarkCategory
    public let raw: String
    public let references: [String]
    /// The spoken language: one recognition code, or two joined by `+` for mixed speech.
    public let language: String?
    /// The sample runs as a translate hold into it.
    public let translationTarget: CleanupBenchmarkTranslationTarget?

    /// The first reference.
    public var expected: String {
        references[0]
    }

    public var translateTo: String? {
        translationTarget?.code
    }

    public init(
        id: String,
        category: CleanupBenchmarkCategory = .uncategorized,
        raw: String,
        references: [String],
        language: String? = nil,
        translationTarget: CleanupBenchmarkTranslationTarget? = nil
    ) {
        self.id = id
        self.category = category
        self.raw = raw
        self.references = references
        self.language = language
        self.translationTarget = translationTarget
    }

    /// The config a cleanup call for this sample is made with: a translation sample is the
    /// app's translate hold into its target.
    public func cleanupConfig(model: String, style: WritingStyle) -> CleanupConfig {
        var config = CleanupConfig(model: model, writingStyle: style)
        if let translationTarget {
            config.translate = true
            config.translationTargetLanguage = Language(rawValue: translationTarget.code)
        }
        return config
    }

    enum CodingKeys: String, CodingKey {
        case id, category, raw, references, language, translateTo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let references = try container.decode([String].self, forKey: .references)
        guard !references.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .references, in: container, debugDescription: "a sample needs a reference")
        }
        let category = try container.decodeIfPresent(CleanupBenchmarkCategory.self, forKey: .category) ?? .uncategorized
        let language = try container.decodeIfPresent(String.self, forKey: .language)
        let translateTo = try container.decodeIfPresent(String.self, forKey: .translateTo)
        try Self.validate(category: category, language: language, hasTarget: translateTo != nil, in: container)
        var target: CleanupBenchmarkTranslationTarget?
        if let translateTo {
            guard let resolved = CleanupBenchmarkTranslationTarget(code: translateTo) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .translateTo, in: container, debugDescription: "\(translateTo) is not a recognition language"
                )
            }
            target = resolved
        }
        self.init(
            id: try container.decode(String.self, forKey: .id),
            category: category,
            raw: try container.decode(String.self, forKey: .raw),
            references: references,
            language: language,
            translationTarget: target
        )
    }

    /// A code the catalogue does not offer would reach the prompt as a bare string, and a key
    /// the category does not take would be silently unused.
    private static func validate(
        category: CleanupBenchmarkCategory,
        language: String?,
        hasTarget: Bool,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws {
        func refuse(_ key: CodingKeys, _ reason: String) -> DecodingError {
            DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: reason)
        }
        guard (category == .translation) == hasTarget else {
            throw refuse(.translateTo, "translateTo belongs to the translation category and only to it")
        }
        let codes = language?.split(separator: "+", omittingEmptySubsequences: false).map(String.init) ?? []
        if let bad = codes.first(where: { !RecognitionLanguageCatalog.isSupported($0) }) {
            throw refuse(.language, "\(bad) is not a recognition language")
        }
        let fits = switch category {
        case .languages: codes.count == 1
        case .mixedLanguages: codes.count == 2
        case .translation: codes.count <= 2
        default: codes.isEmpty
        }
        guard fits else {
            throw refuse(.language, "language does not fit the \(category.rawValue) category")
        }
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
