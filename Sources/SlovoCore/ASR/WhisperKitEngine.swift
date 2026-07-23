import Foundation
import WhisperKit

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
    private let model: String
    private let language: Language
    private let download: Bool
    private let lock = NSLock()
    private var loadedEngine: WhisperKit?

    public init(model: String, language: Language, download: Bool = true) {
        self.model = model
        self.language = language
        self.download = download
    }

    public var isLoaded: Bool {
        lock.withLock { loadedEngine != nil }
    }

    public func load() async throws {
        guard !isLoaded else { return }
        let engine = try await WhisperKit(WhisperKitConfig(
            model: model,
            downloadBase: Self.modelDownloadBase,
            verbose: false,
            logLevel: .error,
            load: true,
            download: download
        ))
        lock.withLock { loadedEngine = engine }
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

    public func makeSpeechStreamingSession() throws -> any SpeechStreamingSession {
        guard let engine = currentEngine else {
            throw TranscriptionError.backendUnavailable
        }
        return try WhisperKitLiveSession(
            engine: engine,
            decodingOptions: Self.decodingOptions(language: language)
        )
    }

    /// The streaming decoder options for `language`. Internal (not private) so
    /// the token-clean contract's first-line layer — `skipSpecialTokens` — is
    /// pinned by a `@testable` unit test without widening the public API.
    ///
    /// `skipSpecialTokens: true` is the FIRST-LINE optimization for the
    /// token-clean text domain: SDK-owned and token-ID-exact, but version-
    /// dependent. The AUTHORITATIVE guarantor is the compose-site sanitizer
    /// (`WhisperKitTranscriptText.strippingSpecialTokens`). `detectLanguage`
    /// pairs with the `.auto` sentinel so mixed RU+EN keeps auto-detecting.
    static func decodingOptions(language: Language) -> DecodingOptions {
        DecodingOptions(
            task: .transcribe,
            language: language.whisperKitLanguageCode,
            detectLanguage: language == .auto,
            skipSpecialTokens: true,
            promptTokens: nil
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
