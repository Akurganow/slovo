import Foundation

// Seam protocols and their typed error domains. Each stage of the
// pipeline — transcribe, clean, inject — is an async seam with a closed error
// enum so callers can switch exhaustively over every failure mode (no `default`).

/// A live-streaming speech recognition session, biased toward the given terms.
///
/// One session at a time: `begin` (key-down) opens the recognizer, `feed` pushes
/// each captured chunk during the hold, `finish` (key-up) finalizes and returns
/// the transcript, and `cancel` tears down without a result.
///
/// `Sendable` so the `actor Orchestrator` can hold it across suspension points
/// without a data race.
public protocol Transcriber: Sendable {
    /// Opens a recognition session biased toward `biasTerms`. Throws if the
    /// backend, locale assets, or engine cannot be brought up.
    func begin(biasTerms: [Term]) async throws

    /// Feeds one live audio chunk into the open session.
    func feed(_ chunk: AudioChunk) async throws

    /// Finalizes the session and returns the trimmed transcript (may be empty).
    func finish() async throws -> String

    /// Tears the session down without producing a transcript.
    func cancel() async
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
/// and `profileFacts`, plus a `Correction` value type) are deferred; the real
/// GRDB adapter will define their exact shapes.
public protocol PersonalizationSource: Sendable {
    func vocabulary(limit: Int) -> [Term]
}
