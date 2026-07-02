import AVFoundation

// Authoritative value types for the dictation pipeline (spec §18.3). These are
// plain data carriers shared across the seam protocols; behavior lives in the
// conforming implementations, not here.

/// The single persisted ASR backend wire value for the shipped WhisperKit runtime.
/// Apple Speech left the runtime and FluidAudio was refuted (no adapter); raw-value
/// additivity keeps any future case wire-safe.
public enum AsrBackend: String, Codable, Equatable, Sendable {
    case whisperKit = "whisperkit"
}

/// The language a transcript or term is in. `auto` chooses the best supported
/// system locale; it is not live per-utterance language detection.
public enum Language: String, Codable, Equatable, Sendable {
    case auto
    case ru
    case en
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
    public static let openRouterModel = "openai/gpt-5.4-nano"
}

/// Tunables for a single cleanup pass.
public struct CleanupConfig: Equatable, Sendable {
    public var model: String
    public var writingStyle: WritingStyle
    public var language: Language

    public init(model: String = CleanupDefaults.openRouterModel, writingStyle: WritingStyle, language: Language) {
        self.model = model
        self.writingStyle = writingStyle
        self.language = language
    }
}

/// The personalization a cleanup pass may draw on. v1 carries only the
/// vocabulary; recent corrections and profile facts arrive in Epic 07.
public struct PersonalizationContext: Sendable {
    public var vocabulary: [Term]

    public init(vocabulary: [Term]) {
        self.vocabulary = vocabulary
    }
}
