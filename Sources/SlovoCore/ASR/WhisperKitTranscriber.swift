import Foundation

/// The streaming WhisperKit dictation session (one session at a time) behind the
/// `Transcriber` seam.
///
/// `warmUp` loads the model once, and it stays loaded. `begin` (key-down) opens
/// native streaming recognition on the loaded model; `feed` converts and
/// immediately forwards each live chunk; `finish` (key-up) finalizes only the
/// unfinished tail and returns the trimmed transcript; `cancel` tears the session
/// down without a result.
///
/// No WhisperKit SDK type crosses this seam: the engine is injected as a
/// `ModelLoading & SpeechStreamingSessionCreating` value and the resampler as
/// `AudioConverting`, so the whole session is driven by fakes in tests.
/// Bias-prompt EFFICACY is verified on-device (docs/release-checklist.md), not here.
public actor WhisperKitTranscriber: Transcriber {
    private let engine: any ModelLoading & SpeechStreamingSessionCreating & Sendable
    private let converter: any AudioConverting

    private var recognitionLanguage: Language
    private var speechSession: (any SpeechStreamingSession)?
    private var loadTask: Task<Void, Error>?

    /// `language` is the recognition language the first session decodes with. Later
    /// changes arrive through `setRecognitionLanguage`, never through a new transcriber.
    public init(
        language: Language = Config.defaults.language,
        engine: some ModelLoading & SpeechStreamingSessionCreating & Sendable,
        converter: sending some AudioConverting
    ) {
        self.recognitionLanguage = language
        self.engine = engine
        self.converter = converter
    }

    /// Loads the model without opening a session; `begin` needs it loaded.
    public func warmUp() async throws {
        try await ensureModelLoaded()
    }

    /// Applies a new recognition language to the next session `begin` opens. The
    /// loaded model is language-independent — the language reaches only the
    /// decoder's per-session options — so a change costs no reload and no rebuilt
    /// pipeline.
    public func setRecognitionLanguage(_ language: Language) {
        recognitionLanguage = language
    }

    public func begin(biasTerms: [Term]) async throws {
        if let speechSession {
            self.speechSession = nil
            await speechSession.cancel()
        }

        do {
            let speechSession = try engine.makeSpeechStreamingSession(
                biasTerms: biasTerms,
                language: recognitionLanguage
            )
            try await speechSession.start()
            self.speechSession = speechSession
        } catch {
            throw Self.mapSessionFailure(error)
        }
    }

    public func feed(_ chunk: AudioChunk) async throws {
        guard let speechSession else { return }
        let samples: [Float]
        do {
            samples = try converter.convert(chunk)
        } catch {
            throw TranscriptionError.audioFormatUnsupported
        }
        do {
            try await speechSession.append(samples)
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.engineFailure(underlying: error)
        }
    }

    public func finish() async throws -> String {
        guard let speechSession else {
            return ""
        }
        self.speechSession = nil
        do {
            let transcript = try await speechSession.finish()
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.engineFailure(underlying: error)
        }
    }

    public func cancel() async {
        guard let speechSession else { return }
        self.speechSession = nil
        await speechSession.cancel()
    }

    /// Single-flight model load: concurrent `warmUp()` calls join ONE in-flight
    /// load, so the engine is constructed exactly once even across actor reentrancy
    /// (avoiding a transient double-load memory spike). A failed load clears the
    /// flight so the next caller retries and surfaces the honest error.
    private func ensureModelLoaded() async throws {
        if let loadTask {
            try await loadTask.value
            return
        }
        let loadTask = Task { [engine] in
            if !engine.isLoaded { try await engine.load() }
        }
        self.loadTask = loadTask
        do {
            try await loadTask.value
        } catch {
            self.loadTask = nil
            throw error
        }
        self.loadTask = nil
    }

    private static func mapSessionFailure(_ error: Error) -> TranscriptionError {
        error as? TranscriptionError ?? .engineFailure(underlying: error)
    }
}
