import Foundation
import WhisperKit
import os

/// The on-device WhisperKit SDK behind model loading and live-session creation,
/// so no WhisperKit type reaches the streaming transcriber.
///
/// Intentionally thin. The model cache is pinned to an app-owned Application
/// Support location via an explicit `downloadBase`: the WhisperKit SDK otherwise
/// downloads under `Documents/huggingface`, which on this un-sandboxed app is a
/// real, possibly iCloud-synced user folder. Bias efficacy is verified
/// on-device, not by unit tests. `@unchecked Sendable` is backed by a lock
/// around the loaded-model pointer, so the transcriber actor can hold it as a
/// `Sendable` engine.
public final class WhisperKitEngine: ModelLoading, SpeechStreamingSessionCreating, @unchecked Sendable {
    private static let diagnosticLog = Logger(subsystem: "com.slovo.app", category: "dictation")

    private let model: String
    private let lock = NSLock()
    private var loadedEngine: WhisperKit?

    public init(model: String) {
        self.model = model
    }

    public var isLoaded: Bool {
        lock.withLock { loadedEngine != nil }
    }

    /// Loads the model from the app cache first, with no request; the download path
    /// runs only when that load fails. It downloads the files that are missing or whose
    /// upstream version changed; a file present but damaged in place is kept
    /// (argmax-oss-swift 1.1.1 at `1bbc57cb`, `HubApi.swift:469-526`, source).
    ///
    /// Logged HERE rather than at the transcriber's single flight: this is the one
    /// place a model is really constructed (and, on a cold cache, downloaded), so a
    /// caller that joins a load in flight — or finds the model resident — emits no
    /// start line, and one start line means one load.
    public func load() async throws {
        guard !isLoaded else { return }
        Self.diagnosticLog.info("asr.modelLoad state=started")
        let loadStartUptime = ProcessInfo.processInfo.systemUptime
        let engine: WhisperKit
        let loadedFromCache: Bool
        do {
            let base = try Self.modelDownloadBase()
            let cached = Self.cachedModelFolder(model: model, base: base)
            do {
                engine = try await WhisperKit(WhisperKitConfig(
                    model: model,
                    downloadBase: base,
                    modelFolder: cached.path(percentEncoded: false),
                    verbose: false,
                    logLevel: .error,
                    load: true,
                    download: false
                ))
                loadedFromCache = true
            } catch {
                engine = try await WhisperKit(WhisperKitConfig(
                    model: model,
                    downloadBase: base,
                    verbose: false,
                    logLevel: .error,
                    load: true,
                    download: true
                ))
                loadedFromCache = false
            }
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
        // Two literal lines: the redaction gate admits no `.public` payload beyond its metric allowlist.
        if loadedFromCache {
            Self.diagnosticLog.info("asr.modelLoad state=finished ms=\(loadMs, privacy: .public) source=cache")
        } else {
            Self.diagnosticLog.info("asr.modelLoad state=finished ms=\(loadMs, privacy: .public) source=download")
        }
    }

    private static func elapsedMs(since startUptime: TimeInterval) -> Int {
        Int((ProcessInfo.processInfo.systemUptime - startUptime) * 1_000)
    }

    /// App-owned model cache under Application Support, overriding the WhisperKit
    /// SDK default (`Documents/huggingface` — a real, un-sandboxed, possibly
    /// iCloud-synced user folder). Throws when Application Support cannot be
    /// created, so a failure fails the load instead of moving the cache to the SDK
    /// default.
    private static func modelDownloadBase() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "slovo/models", directoryHint: .isDirectory)
    }

    /// The folder WhisperKit's download writes `model` into under `base`. The SDK names the
    /// repository folder; the `openai_whisper-` prefix is the Hub's folder name for every
    /// model of that repository Slovo offers (argmax-oss-swift 1.1.1 at `1bbc57cb`,
    /// `WhisperKit.swift:264-303`, source). A model id under another prefix, which only a
    /// hand edit can produce, misses the cache and loads through the download path.
    static func cachedModelFolder(model: String, base: URL) -> URL {
        HubApiWrapper(downloadBase: base)
            .localRepoLocation(HubApiWrapper.Repo(id: "argmaxinc/whisperkit-coreml"))
            .appending(path: "openai_whisper-\(model)", directoryHint: .isDirectory)
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
