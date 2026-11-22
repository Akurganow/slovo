import Foundation

/// The streaming WhisperKit dictation session (one session at a time) behind the
/// `Transcriber` seam.
///
/// `begin` (key-down) loads the model and starts native streaming recognition;
/// `feed` converts and immediately forwards each live chunk; `finish` (key-up)
/// finalizes only the unfinished tail and returns the trimmed transcript;
/// `cancel` tears the session down without a result. The model loads once and
/// stays loaded; `warmUp` preloads it without opening a session.
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

    /// Whether `begin` would reuse an already-loaded model. Read straight from the
    /// engine, so it cannot drift from what `begin` will actually do.
    public var isModelResident: Bool {
        engine.isLoaded
    }

    /// Preloads the model without opening a session, so the first dictation skips
    /// the cold load. A subsequent `begin` reuses the warm model (no reload).
    public func warmUp() async throws {
        do {
            try await ensureModelLoaded()
        } catch {
            throw Self.mapLoadFailure(error)
        }
    }

    /// Applies a new recognition language to the next session `begin` opens. `begin`
    /// latches the value it is entered with, so a push landing during its model load
    /// cannot redefine the dictation already opening. A push landing earlier, inside
    /// `Orchestrator.beginCapture`, still reaches that dictation — the window its own
    /// `sessionRunsCleaner` latch already declares accepted. The loaded model is
    /// language-independent — the language reaches only the decoder's per-session
    /// options — so a change costs no reload and no rebuilt pipeline.
    public func setRecognitionLanguage(_ language: Language) {
        recognitionLanguage = language
    }

    public func begin(biasTerms: [Term]) async throws {
        // Latched BEFORE the first suspension: `ensureModelLoaded()` can park for a
        // whole cold load, and the actor admits `setRecognitionLanguage` there — read
        // afterwards, a push would silently redefine the session already opening.
        let sessionLanguage = recognitionLanguage
        if let speechSession {
            self.speechSession = nil
            await speechSession.cancel()
        }
        do {
            try await ensureModelLoaded()
        } catch {
            throw Self.mapLoadFailure(error)
        }

        do {
            let speechSession = try engine.makeSpeechStreamingSession(
                biasTerms: biasTerms,
                language: sessionLanguage
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

    /// Single-flight model load: concurrent `warmUp()`/`begin()` join ONE in-flight
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

    private static func mapLoadFailure(_ error: Error) -> TranscriptionError {
        error as? TranscriptionError ?? .backendUnavailable
    }

    private static func mapSessionFailure(_ error: Error) -> TranscriptionError {
        error as? TranscriptionError ?? .engineFailure(underlying: error)
    }
}
