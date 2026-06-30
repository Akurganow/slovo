import AVFoundation
import Foundation

// Authoritative value types for the dictation pipeline (spec §18.3). These are
// plain data carriers shared across the seam protocols; behavior lives in the
// conforming implementations, not here.

/// The language a transcript or term is in. `auto` defers detection to the engine.
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

/// How aggressively the cleaner rewrites the transcript toward written prose.
public enum WritingStyle: String, Codable, Equatable, Sendable {
    case formal
    case casual
    case veryCasual = "very-casual"
}

/// Cloud cleanup provider selected by configuration.
public enum CleanupProvider: String, Codable, Equatable, Sendable {
    case anthropic
    case openAI = "openai"
}

/// Tunables for a single cleanup pass.
public struct CleanupConfig: Equatable, Sendable {
    public var model: String
    public var writingStyle: WritingStyle
    public var language: Language

    public init(model: String = "claude-haiku-4-5", writingStyle: WritingStyle, language: Language) {
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
