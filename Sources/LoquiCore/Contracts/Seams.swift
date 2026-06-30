import Foundation

// Seam protocols and their typed error domains (spec §18.3). Each stage of the
// pipeline — transcribe, clean, inject — is an async seam with a closed error
// enum so callers can switch exhaustively over every failure mode (no `default`).

/// Produces text from a captured audio buffer, biased toward the given terms.
///
/// `Sendable` so the `actor Orchestrator` can hold it across suspension points
/// without a data race.
public protocol Transcriber: Sendable {
    func transcribe(_ audio: AudioBuffer, biasTerms: [Term]) async throws -> String
}

/// Failure modes of a transcription attempt.
///
/// `Equatable` is manual because `engineFailure(underlying: Error)` wraps a
/// non-`Equatable` `Error`, which blocks synthesis. Two `engineFailure` values
/// are equal by case (the wrapped cause is ignored); the other cases compare by
/// their values.
public enum TranscriptionError: Error, Equatable, Sendable {
    case backendUnavailable
    case assetMissing(locale: String)
    case audioFormatUnsupported
    case engineFailure(underlying: Error)

    public static func == (lhs: TranscriptionError, rhs: TranscriptionError) -> Bool {
        switch (lhs, rhs) {
        case (.backendUnavailable, .backendUnavailable):
            return true
        case (.assetMissing(let lhsLocale), .assetMissing(let rhsLocale)):
            return lhsLocale == rhsLocale
        case (.audioFormatUnsupported, .audioFormatUnsupported):
            return true
        case (.engineFailure, .engineFailure):
            return true
        case (.backendUnavailable, _),
             (.assetMissing, _),
             (.audioFormatUnsupported, _),
             (.engineFailure, _):
            return false
        }
    }
}

/// Rewrites a raw transcript into clean prose under the given config/context.
/// `Sendable` so the `actor Orchestrator` can hold it (see `Transcriber`).
public protocol Cleaner: Sendable {
    func clean(_ raw: String, config: CleanupConfig, context: PersonalizationContext) async throws -> String
}

/// Failure modes of a cleanup attempt.
public enum CleanupError: Error, Sendable {
    case offline
    case missingKey
    case rateLimited(retryAfter: TimeInterval?)
    case apiError(status: Int)
    case refused
}

/// Inserts finished text into the focused application.
/// `Sendable` so the `actor Orchestrator` can hold it (see `Transcriber`).
public protocol Injector: Sendable {
    func insert(_ text: String) async throws
}

/// Failure modes of a text-insertion attempt.
public enum InjectionError: Error, Equatable, Sendable {
    case accessibilityDenied
    case secureInputActive
    case pasteFailed
}

/// Read-port over the user's personalization store.
///
/// v1 exposes only the bias vocabulary. The v1.x members (`recentCorrections`
/// and `profileFacts`, plus a `Correction` value type) land in Epic 07, where
/// the real GRDB adapter defines their exact shapes (GAP-1: deferred).
public protocol PersonalizationSource: Sendable {
    func vocabulary(limit: Int) -> [Term]
}
