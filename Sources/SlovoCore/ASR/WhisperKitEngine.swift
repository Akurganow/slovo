import Foundation
import WhisperKit

/// The on-device WhisperKit SDK behind the `ModelLoading` + `SpeechDecoding`
/// seams, so no WhisperKit type reaches the streaming transcriber.
///
/// Intentionally thin. The model cache is pinned to an app-owned Application
/// Support location via an explicit `downloadBase`: the WhisperKit SDK otherwise
/// downloads under the user's home Hugging Face cache, which on this un-sandboxed
/// app is a real, possibly iCloud-synced user folder. Bias efficacy is verified
/// on-device (L4), not by unit tests. `@unchecked Sendable` is backed by a lock
/// around the loaded-model pointer, so the transcriber actor can hold it as a
/// `Sendable` engine.
public final class WhisperKitEngine: ModelLoading, SpeechDecoding, @unchecked Sendable {
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

    public func encodePromptTokens(_ prompt: String) -> [Int] {
        guard let tokenizer = currentEngine?.tokenizer else { return [] }
        return tokenizer.encode(text: prompt)
    }

    public func decode(samples: [Float], promptTokens: [Int]?) async throws -> String {
        guard let engine = currentEngine else {
            throw TranscriptionError.backendUnavailable
        }
        let results = try await engine.transcribe(
            audioArray: samples,
            decodeOptions: DecodingOptions(
                task: .transcribe,
                language: language.whisperKitLanguageCode,
                detectLanguage: language == .auto,
                promptTokens: promptTokens
            )
        )
        return results.map(\.text).joined(separator: " ")
    }

    private var currentEngine: WhisperKit? {
        lock.withLock { loadedEngine }
    }
}

private extension Language {
    /// The fixed language code passed to WhisperKit, or `nil` for `.auto` (which
    /// pairs with `detectLanguage`).
    var whisperKitLanguageCode: String? {
        switch self {
        case .auto: nil
        case .ru: "ru"
        case .en: "en"
        }
    }
}
