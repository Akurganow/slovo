import AVFoundation

// Authoritative value types for the dictation pipeline. These are
// plain data carriers shared across the seam protocols; behavior lives in the
// conforming implementations, not here.

/// The single persisted ASR backend wire value for the shipped WhisperKit runtime.
/// Apple Speech left the runtime and FluidAudio was refuted (no adapter); raw-value
/// additivity keeps any future case wire-safe.
public enum AsrBackend: String, Codable, Equatable, Sendable {
    case whisperKit = "whisperkit"
}

/// The language a transcript or term is in, carried as a bare WhisperKit language
/// code. `auto` chooses the best supported system locale and enables per-utterance
/// detection; any other value pins one specific code (e.g. "ru", "ja").
///
/// String-backed rather than a fixed case list so the full WhisperKit catalog
/// round-trips without this type enumerating languages — the supported set lives in
/// `RecognitionLanguageCatalog`, sourced from WhisperKit itself.
///
/// - Important: `auto` is a SENTINEL, not a WhisperKit language code. Every
///   language-consuming site (the engine's code mapping, config validation) must
///   special-case it. Moving off the former enum traded compile-time exhaustiveness
///   for an open code space, so that special-casing is now a convention this doc
///   pins rather than a guarantee the compiler enforces.
public struct Language: RawRepresentable, Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The bare code, so interpolating a `Language` renders as its wire value
    /// ("en", "auto") rather than a reflected struct description.
    public var description: String { rawValue }

    // Persisted as a single bare string ("auto", "ru", "ja"), matching the former
    // String-enum wire so existing stored configs decode unchanged. Every string is
    // accepted here; whether a value is an offered language is decided by
    // `RecognitionLanguageCatalog`, not the wire decoder.
    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension Language {
    /// Detect the language per utterance instead of pinning one code.
    static let auto = Language(rawValue: "auto")
    static let ru = Language(rawValue: "ru")
    static let en = Language(rawValue: "en")
}

/// One personalization vocabulary row: a term the user dictates, an optional
/// expansion to substitute, the language it applies to, and a bias weight.
public struct Term: Sendable {
    public let term: String
    public let expansion: String?
    public let lang: Language
    public let weight: Int

    public init(term: String, expansion: String?, lang: Language, weight: Int) {
        self.term = term
        self.expansion = expansion
        self.lang = lang
        self.weight = weight
    }
}

/// A captured audio span handed to a `Transcriber`: raw float samples plus the
/// format describing their sample rate and channel layout.
///
/// `@unchecked Sendable`: `[Float]` is `Sendable`, and `AVAudioFormat` is an
/// immutable Apple class (not marked `Sendable` in the SDK) that is safe to share
/// — the value is never mutated after construction.
public struct AudioBuffer: @unchecked Sendable {
    public let samples: [Float]
    public let format: AVAudioFormat

    public init(samples: [Float], format: AVAudioFormat) {
        self.samples = samples
        self.format = format
    }
}

/// One live microphone chunk streamed from an `AudioRecorder` to a `Transcriber`
/// during a hold. It carries the tap's NATIVE `AVAudioPCMBuffer` unchanged;
/// conversion to the analyzer's format happens once inside the transcriber.
///
/// `@unchecked Sendable`: `AVAudioPCMBuffer` is not marked `Sendable` in the SDK,
/// but each chunk wraps a freshly copied buffer that is handed off and never
/// mutated after construction.
public struct AudioChunk: @unchecked Sendable {
    public let buffer: AVAudioPCMBuffer

    public init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

/// How aggressively the cleaner rewrites the transcript toward written prose.
public enum WritingStyle: String, Codable, Equatable, Sendable {
    case formal
    case casual
    case veryCasual = "very-casual"
}

public enum CleanupDefaults {
    public static let openRouterModel = "openai/gpt-5.6-luna"
}

/// Tunables for a single cleanup pass.
public struct CleanupConfig: Equatable, Sendable {
    public var model: String
    public var writingStyle: WritingStyle
    public var language: Language
    /// When on, the orchestrator runs the on-device spell pass and passes its
    /// findings to the model as advisory hints. The input-language hint is
    /// unaffected — it has no toggle.
    public var useSpellCheckHints: Bool

    public init(
        model: String = CleanupDefaults.openRouterModel,
        writingStyle: WritingStyle,
        language: Language,
        useSpellCheckHints: Bool = true
    ) {
        self.model = model
        self.writingStyle = writingStyle
        self.language = language
        self.useSpellCheckHints = useSpellCheckHints
    }
}

/// The personalization a cleanup pass may draw on. v1 carries only the
/// vocabulary; recent corrections and profile facts arrive in a later version.
public struct PersonalizationContext: Sendable {
    public var vocabulary: [Term]

    public init(vocabulary: [Term]) {
        self.vocabulary = vocabulary
    }
}
