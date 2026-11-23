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
    /// Applies a new recognition language to the NEXT session. Part of the seam
    /// because the language is session state, not model state: the loaded model
    /// decodes any language, so a change must never cost a reload.
    func setRecognitionLanguage(_ language: Language) async

    /// Opens a recognition session biased toward `biasTerms` on the loaded model.
    /// Throws if the session cannot open, `backendUnavailable` when no model is loaded.
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
/// are equal by case (the wrapped cause is ignored); the other cases carry no
/// value.
public enum TranscriptionError: Error, Equatable, Sendable {
    case backendUnavailable
    case audioFormatUnsupported
    case engineFailure(underlying: Error)

    public static func == (lhs: TranscriptionError, rhs: TranscriptionError) -> Bool {
        switch (lhs, rhs) {
        case (.backendUnavailable, .backendUnavailable):
            return true
        case (.audioFormatUnsupported, .audioFormatUnsupported):
            return true
        case (.engineFailure, .engineFailure):
            return true
        case (.backendUnavailable, _),
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
    /// Cleans with advisory on-device hints. The default implementation below DROPS
    /// the hints and forwards to the 3-arg `clean`; a cleaner that must act on hints
    /// (e.g. the OpenRouter cleaner feeding `PromptBuilder`) MUST override this
    /// requirement — inheriting the default silently ignores them.
    func clean(
        _ raw: String,
        config: CleanupConfig,
        context: PersonalizationContext,
        hints: CleanupHints
    ) async throws -> String
}

public extension Cleaner {
    /// Default: drop the hints and clean as before. Override to consume them.
    func clean(
        _ raw: String,
        config: CleanupConfig,
        context: PersonalizationContext,
        hints: CleanupHints
    ) async throws -> String {
        try await clean(raw, config: config, context: context)
    }
}

/// Failure modes of a cleanup attempt.
public enum CleanupError: Error, Sendable {
    case transport
    case missingKey
    case rateLimited(retryAfter: TimeInterval?)
    case apiError(status: Int)
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
    /// The user's whole bias vocabulary, bias-rank descending (manual weight plus
    /// decayed miss boost; weight then term break ties — identical to weight order
    /// when no misses are stored) — consumers budget it themselves, so the order
    /// must be stable. The
    /// ordering is load-bearing only on the ASR path, where arrival order alone
    /// decides which terms reach the bias prompt's token budget; the cleanup builder
    /// re-sorts defensively, and fakes may hand back plain arrival order.
    func vocabulary() -> [Term]
}

/// Sink for one dictation's detected vocabulary misses (folded term keys).
/// Non-throwing by contract: recording is fire-and-forget off the hot path —
/// a failure is logged coarsely inside the adapter and never disturbs the
/// injection pipeline (a throwing signature would force a swallowed `try?`
/// at the single call site).
public protocol TermMissRecording: Sendable {
    func recordMisses(_ termKeys: [String]) async
}
