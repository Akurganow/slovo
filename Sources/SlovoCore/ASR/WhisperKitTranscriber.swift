import Foundation

/// The streaming WhisperKit dictation session (one session at a time) behind the
/// `Transcriber` seam.
///
/// `begin` (key-down) loads the model and encodes the bias prompt; `feed`
/// converts and accumulates each live chunk during the hold; `finish` (key-up)
/// decodes the accumulation exactly once and returns the trimmed transcript;
/// `cancel` tears the session down without decoding. It builds and owns its
/// `ModelLifecycle` internally — after each use the model is kept per
/// `configuration.keepWarmSeconds` (resident by default, an idle window, or
/// released immediately). `warmUp` preloads the model without opening a session.
///
/// No WhisperKit SDK type crosses this seam: the engine is injected as a
/// `ModelLoading & SpeechDecoding` value, the resampler as `AudioConverting`, and
/// the idle-timing source as `Clock`, so the whole session is driven by fakes in
/// tests. Bias EFFICACY is verified on-device (L4), not here — see
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

    /// Whether the bias-prompt field has been verified to steer recognition. Token
    /// plumbing is unit-tested; efficacy stays an on-device (L4) check.
    public enum BiasFieldVerification: Equatable, Sendable {
        case requiresL4Verification
    }

    public static let biasFieldVerification: BiasFieldVerification = .requiresL4Verification

    private let configuration: Configuration
    private let engine: any ModelLoading & SpeechDecoding & Sendable
    private let converter: any AudioConverting
    private let clock: any Clock
    private let lifecycle: ModelLifecycle

    private var sessionOpen = false
    private var accumulatedSamples: [Float] = []
    private var promptTokens: [Int]?
    private var releaseTask: Task<Void, Never>?
    private var releaseGeneration = 0
    private var loadTask: Task<Void, Error>?

    public init(
        configuration: Configuration = .defaults,
        engine: some ModelLoading & SpeechDecoding & Sendable,
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
        accumulatedSamples = []
        promptTokens = nil
        sessionOpen = true

        do {
            try await ensureModelLoaded()
        } catch {
            sessionOpen = false
            throw Self.mapLoadFailure(error)
        }

        // Bias-prompt injection is DISABLED: WhisperKit + the turbo model return
        // deterministically EMPTY output for ANY non-nil DecodingOptions.promptTokens,
        // proven on the A/B stand with real voice on 2026-07-02 — a non-nil prompt
        // silently breaks dictation. So `promptTokens` stays nil (set above) and
        // decode runs unbiased. The budgeted `WhisperKitBiasPromptBuilder` and its
        // tests are kept intact as the guard for re-enabling once the SDK prompt path
        // works again (tracked follow-up); `biasTerms` still reaches the cleaner via
        // the orchestrator, so vocabulary is not lost meanwhile.
    }

    public func feed(_ chunk: AudioChunk) async throws {
        guard sessionOpen else { return }
        do {
            accumulatedSamples.append(contentsOf: try converter.convert(chunk))
        } catch {
            throw TranscriptionError.audioFormatUnsupported
        }
    }

    /// Note: the streaming converter's final ~235-frame (~15 ms) delay-line residue
    /// is never flushed here — accepted as immaterial for push-to-talk (trailing
    /// silence, sub-phoneme). The reused converter also carries that ~15 ms of the
    /// previous session's tail into the next session's first chunk: same-user,
    /// in-memory, acoustically negligible; documented, not fixed.
    public func finish() async throws -> String {
        guard sessionOpen else { return "" }
        sessionOpen = false
        // Empty accumulation is a non-error empty result: skip decode entirely
        // (real WhisperKit may throw on an empty sample array).
        guard !accumulatedSamples.isEmpty else {
            endUse()
            return ""
        }
        do {
            let transcript = try await engine.decode(samples: accumulatedSamples, promptTokens: promptTokens)
            endUse()
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            endUse()
            throw TranscriptionError.engineFailure(underlying: error)
        }
    }

    public func cancel() async {
        guard sessionOpen else { return }
        sessionOpen = false
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

    /// Finalizes the lifecycle exactly once per session and clears accumulation.
    private func endUse() {
        accumulatedSamples = []
        promptTokens = nil
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
}
