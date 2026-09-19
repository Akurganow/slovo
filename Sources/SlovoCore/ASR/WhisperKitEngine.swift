import Foundation
import WhisperKit
import os

/// The on-device WhisperKit SDK behind model loading and live-session creation,
/// so no WhisperKit type reaches the streaming transcriber.
///
/// Intentionally thin. The model cache is pinned to an app-owned Application
/// Support location via an explicit `downloadBase`: the WhisperKit SDK otherwise
/// downloads under the user's home Hugging Face cache, which on this un-sandboxed
/// app is a real, possibly iCloud-synced user folder. Bias efficacy is verified
/// on-device, not by unit tests. `@unchecked Sendable` is backed by a lock
/// around the loaded-model pointer, so the transcriber actor can hold it as a
/// `Sendable` engine.
public final class WhisperKitEngine: ModelLoading, SpeechStreamingSessionCreating, @unchecked Sendable {
    private static let diagnosticLog = Logger(subsystem: "com.slovo.app", category: "dictation")

    private let model: String
    private let download: Bool
    private let lock = NSLock()
    private var loadedEngine: WhisperKit?

    public init(model: String, download: Bool = true) {
        self.model = model
        self.download = download
    }

    public var isLoaded: Bool {
        lock.withLock { loadedEngine != nil }
    }

    /// Logged HERE rather than at the transcriber's single flight: this is the one
    /// place a model is really constructed (and, on a cold cache, downloaded), so a
    /// caller that joins a load in flight — or finds the model resident — emits no
    /// start line, and one start line means one load.
    public func load() async throws {
        guard !isLoaded else { return }
        Self.diagnosticLog.info("asr.modelLoad state=started")
        let loadStartUptime = ProcessInfo.processInfo.systemUptime
        let engine: WhisperKit
        do {
            engine = try await WhisperKit(WhisperKitConfig(
                model: model,
                downloadBase: Self.modelDownloadBase,
                verbose: false,
                logLevel: .error,
                load: true,
                download: download
            ))
        } catch {
            let loadMs = Self.elapsedMs(since: loadStartUptime)
            Self.diagnosticLog.error(
                """
                asr.modelLoad state=failed ms=\(loadMs, privacy: .public) \
                error=\(error.localizedDescription, privacy: .private)
                """
            )
            throw error
        }
        let loadMs = Self.elapsedMs(since: loadStartUptime)
        lock.withLock { loadedEngine = engine }
        Self.diagnosticLog.info("asr.modelLoad state=finished ms=\(loadMs, privacy: .public)")
    }

    private static func elapsedMs(since startUptime: TimeInterval) -> Int {
        Int((ProcessInfo.processInfo.systemUptime - startUptime) * 1_000)
    }

    /// App-owned model cache under Application Support, overriding the WhisperKit
    /// SDK default (the user's home Hugging Face cache — a real, un-sandboxed,
    /// possibly iCloud-synced user folder).
    private static var modelDownloadBase: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "slovo/models", directoryHint: .isDirectory)
    }

    public func release() {
        lock.withLock { loadedEngine = nil }
    }

    public func makeSpeechStreamingSession(biasTerms: [Term], language: Language) throws -> any SpeechStreamingSession {
        guard let engine = currentEngine else {
            throw TranscriptionError.backendUnavailable
        }
        return try WhisperKitLiveSession(
            engine: engine,
            decodingOptions: Self.decodingOptions(language: language, biasTerms: biasTerms) { text in
                engine.tokenizer?.encode(text: text) ?? []
            }
        )
    }

    /// The streaming decoder options for `language`, biased toward `biasTerms`
    /// (empty runs unbiased). Pure and internal (not private) so a `@testable`
    /// unit test pins BOTH the token-clean contract's first-line layer —
    /// `skipSpecialTokens` — and the bias wiring, without widening the public API
    /// or loading a model.
    ///
    /// `skipSpecialTokens: true` is the FIRST-LINE optimization for the
    /// token-clean text domain: SDK-owned and token-ID-exact, but version-
    /// dependent. The AUTHORITATIVE guarantor is the compose-site sanitizer
    /// (`WhisperKitTranscriptText.strippingSpecialTokens`). `detectLanguage`
    /// pairs with the `.auto` sentinel so mixed RU+EN keeps auto-detecting.
    static func decodingOptions(
        language: Language,
        biasTerms: [Term],
        tokenizer: (String) -> [Int]
    ) -> DecodingOptions {
        DecodingOptions(
            task: .transcribe,
            language: language.whisperKitLanguageCode,
            detectLanguage: language == .auto,
            skipSpecialTokens: true,
            promptTokens: WhisperKitBiasPromptBuilder.promptTokens(for: biasTerms, tokenizer: tokenizer)
        )
    }

    private var currentEngine: WhisperKit? {
        lock.withLock { loadedEngine }
    }
}

extension Language {
    /// The language code passed to WhisperKit, or `nil` for the `.auto` sentinel
    /// (which pairs with `detectLanguage` so mixed RU+EN keeps auto-detecting). Any
    /// non-auto value is already a WhisperKit code. Internal, not private, so the
    /// mapping is pinned by a `@testable` unit test without widening the public API.
    var whisperKitLanguageCode: String? {
        self == .auto ? nil : rawValue
    }
}
