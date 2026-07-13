import Foundation

/// The streaming WhisperKit dictation session (one session at a time) behind the
/// `Transcriber` seam.
///
/// `begin` (key-down) loads the model and starts native streaming recognition;
/// `feed` converts and immediately forwards each live chunk; `finish` (key-up)
/// finalizes only the unfinished tail and returns the trimmed transcript;
/// `cancel` tears the session down without a result. It builds and owns its
/// `ModelLifecycle` internally — after each use the model is kept per
/// `configuration.keepWarmSeconds` (resident by default, an idle window, or
/// released immediately). `warmUp` preloads the model without opening a session.
///
/// No WhisperKit SDK type crosses this seam: the engine is injected as a
/// `ModelLoading & SpeechStreamingSessionCreating` value, the resampler as `AudioConverting`, and
/// the idle-timing source as `Clock`, so the whole session is driven by fakes in
/// tests. Bias EFFICACY is verified on-device, not here — see
/// `biasFieldVerification`.
public actor WhisperKitTranscriber: Transcriber {
    public struct Configuration: Equatable, Sendable {
        public static let defaults = Configuration()

        /// Model retention: `nil` keeps the model resident (fastest first word),
        /// `0` releases immediately on key-up, a positive value is the idle-seconds
        /// window before release.
        public var keepWarmSeconds: Int?

        public init(keepWarmSeconds: Int? = Config.defaults.keepWarmSeconds) {
            self.keepWarmSeconds = keepWarmSeconds
        }
    }

    /// Whether the disabled bias-prompt path has been verified safe to re-enable.
    /// Efficacy stays an on-device check.
    public enum BiasFieldVerification: Equatable, Sendable {
        case requiresL4Verification
    }

    public static let biasFieldVerification: BiasFieldVerification = .requiresL4Verification

    private let configuration: Configuration
    private let engine: any ModelLoading & SpeechStreamingSessionCreating & Sendable
    private let converter: any AudioConverting
    private let clock: any Clock
    private let lifecycle: ModelLifecycle

    private var speechSession: (any SpeechStreamingSession)?
    private var releaseTask: Task<Void, Never>?
    private var releaseGeneration = 0
    private var loadTask: Task<Void, Error>?

    public init(
        configuration: Configuration = .defaults,
        engine: some ModelLoading & SpeechStreamingSessionCreating & Sendable,
        converter: sending some AudioConverting,
        clock: some Clock
    ) {
        self.configuration = configuration
        self.engine = engine
        self.converter = converter
        self.clock = clock
        self.lifecycle = ModelLifecycle(
            model: engine,
            keepWarmSeconds: configuration.keepWarmSeconds.map(TimeInterval.init),
            clock: clock
        )
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

    public func begin(biasTerms: [Term]) async throws {
        supersedePendingRelease()
        if let speechSession {
            self.speechSession = nil
            await speechSession.cancel()
        }
        do {
            try await ensureModelLoaded()
        } catch {
            throw Self.mapLoadFailure(error)
        }

        // Bias-prompt injection is DISABLED: WhisperKit + the turbo model return
        // deterministically EMPTY output for ANY non-nil DecodingOptions.promptTokens,
        // proven on the A/B stand with real voice on 2026-07-02 — a non-nil prompt
        // silently breaks dictation. The live session therefore runs unbiased. The
        // budgeted `WhisperKitBiasPromptBuilder` and its
        // tests are kept intact as the guard for re-enabling once the SDK prompt path
        // works again (tracked follow-up); `biasTerms` still reaches the cleaner via
        // the orchestrator, so vocabulary is not lost meanwhile.
        do {
            let speechSession = try engine.makeSpeechStreamingSession()
            try await speechSession.start()
            self.speechSession = speechSession
        } catch {
            endUse()
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
            endUse()
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as TranscriptionError {
            endUse()
            throw error
        } catch {
            endUse()
            throw TranscriptionError.engineFailure(underlying: error)
        }
    }

    public func cancel() async {
        guard let speechSession else { return }
        self.speechSession = nil
        await speechSession.cancel()
        endUse()
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
        let loadTask = Task { [lifecycle] in
            try await lifecycle.willUse()
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

    /// Finalizes the lifecycle exactly once per session and clears live state.
    private func endUse() {
        lifecycle.didFinishUse()
        scheduleRelease()
    }

    /// With a positive keep-warm window, schedules a generation-guarded release
    /// that fires `tick()` after the idle window; a new `begin` supersedes it. A
    /// resident (`nil`) or zero window schedules nothing — the lifecycle already
    /// kept the model resident or released it inside `didFinishUse()`.
    private func scheduleRelease() {
        supersedePendingRelease()
        guard let keepWarmSeconds = configuration.keepWarmSeconds, keepWarmSeconds > 0 else { return }

        let generation = releaseGeneration
        releaseTask = Task { [weak self, clock] in
            try? await clock.sleep(for: TimeInterval(keepWarmSeconds))
            await self?.releaseIfIdle(generation: generation)
        }
    }

    private func releaseIfIdle(generation: Int) {
        guard generation == releaseGeneration else { return }
        lifecycle.tick()
        releaseTask = nil
    }

    private func supersedePendingRelease() {
        releaseTask?.cancel()
        releaseTask = nil
        releaseGeneration += 1
    }

    private static func mapLoadFailure(_ error: Error) -> TranscriptionError {
        error as? TranscriptionError ?? .backendUnavailable
    }

    private static func mapSessionFailure(_ error: Error) -> TranscriptionError {
        error as? TranscriptionError ?? .engineFailure(underlying: error)
    }
}
