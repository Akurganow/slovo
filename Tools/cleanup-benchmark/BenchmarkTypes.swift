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
    /// Plain samples whose point is the vocabulary they carry.
    case vocabulary
    /// Plain samples whose point is the on-device hints they carry.
    case hints
}

/// The language a translation sample is cleaned into: its catalogue code and the name the
/// translate prompt and the judge use.
public struct CleanupBenchmarkTranslationTarget: Equatable, Sendable {
    public let code: String
    public let name: String

    /// Nil for a code the catalogue does not offer.
    public init?(code: String) {
        guard RecognitionLanguageCatalog.isSupported(code) else {
            return nil
        }
        self.code = code
        self.name = PromptBuilder.translationTargetName(for: code)
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
    /// The vocabulary the cleanup call carries; empty when the sample has none.
    public let vocabulary: [CleanupBenchmarkVocabularyEntry]
    /// The on-device hints the cleanup call carries; `CleanupHints()` when the sample has none.
    public let hints: CleanupHints

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
        translationTarget: CleanupBenchmarkTranslationTarget? = nil,
        vocabulary: [CleanupBenchmarkVocabularyEntry] = [],
        hints: CleanupHints = CleanupHints()
    ) {
        self.id = id
        self.category = category
        self.raw = raw
        self.references = references
        self.language = language
        self.translationTarget = translationTarget
        self.vocabulary = vocabulary
        self.hints = hints
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
        case id, category, raw, references, language, translateTo, vocabulary, hints
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
        let raw = try container.decode(String.self, forKey: .raw)
        let (vocabulary, hints) = try Self.decodeVocabularyAndHints(category: category, raw: raw, from: container)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            category: category,
            raw: raw,
            references: references,
            language: language,
            translationTarget: target,
            vocabulary: vocabulary,
            hints: hints
        )
    }

    /// A blank term or an empty hints object would reach the prompt as nothing, and a spell token
    /// the raw does not hold would plant a hint the on-device checker could never produce.
    private static func decodeVocabularyAndHints(
        category: CleanupBenchmarkCategory,
        raw: String,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> ([CleanupBenchmarkVocabularyEntry], CleanupHints) {
        func refuse(_ key: CodingKeys, _ reason: String) -> DecodingError {
            DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: reason)
        }
        let vocabulary = try container.decodeIfPresent([CleanupBenchmarkVocabularyEntry].self, forKey: .vocabulary) ?? []
        guard vocabulary.allSatisfy({ !$0.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw refuse(.vocabulary, "a vocabulary term is empty")
        }
        guard category != .vocabulary || !vocabulary.isEmpty else {
            throw refuse(.vocabulary, "a vocabulary sample carries no vocabulary: add one or change its category")
        }
        var hints = CleanupHints()
        if let object = try container.decodeIfPresent(CleanupBenchmarkHintsObject.self, forKey: .hints) {
            guard object.inputLocale != nil || object.spell != nil || object.grammar != nil else {
                throw refuse(.hints, "hints holds nothing: leave it out or give it a member")
            }
            guard object.spell?.isEmpty != true, object.grammar?.isEmpty != true else {
                throw refuse(.hints, "hints holds an empty spell or grammar list: leave the member out")
            }
            if let missing = object.spell?.first(where: { $0.token.isEmpty || !raw.contains($0.token) }) {
                throw refuse(.hints, "spell token \"\(missing.token)\" does not occur in the raw")
            }
            hints = CleanupHints(
                inputLocale: object.inputLocale,
                spellFindings: (object.spell ?? []).map { SpellFinding(token: $0.token, guesses: $0.guesses ?? []) },
                grammarFindings: (object.grammar ?? []).map {
                    GrammarFinding(fragment: $0.fragment, message: $0.message, corrections: $0.corrections ?? [])
                }
            )
        }
        guard category != .hints || hints != CleanupHints() else {
            throw refuse(.hints, "a hints sample carries no hints: add them or change its category")
        }
        return (vocabulary, hints)
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
    public let clean: @Sendable (String, CleanupConfig, PersonalizationContext, CleanupHints) async throws -> CleanupBenchmarkCleaned

    @preconcurrency
    public init(
        provider: String,
        model: String,
        clean: @escaping @Sendable (String, CleanupConfig, PersonalizationContext, CleanupHints) async throws -> CleanupBenchmarkCleaned
    ) {
        self.provider = provider
        self.model = model
        self.clean = clean
    }

    /// A candidate whose provider reports no cost and takes no hints.
    public init(provider: String, model: String, cleaner: any Cleaner) {
        self.init(provider: provider, model: model) { raw, config, context, _ in
            CleanupBenchmarkCleaned(text: try await cleaner.clean(raw, config: config, context: context))
        }
    }

    public var name: String {
        "\(provider):\(model)"
    }
}
