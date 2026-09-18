/// The process's ONE speech model, projected by every pipeline composition.
///
/// Slovo rebuilds the pipeline whenever setup changes — a granted Microphone or
/// Accessibility permission, Retry Setup, the hotkey retry. Each rebuild used to
/// construct its own engine and start its own preload, so a first run could have
/// several loads of the same artifact in flight at once, each downloading into the
/// same cache while the user was still granting permissions. The model outlives
/// every composition instead: it is built once per launch, and a rebuild only asks
/// it for a fresh warm-up.
///
/// That warm-up task is minted PER composition rather than stored once, and the
/// difference is load-bearing. `WhisperKitTranscriber` runs a single-flight load
/// and does not cache a failure, so a rebuild during a load joins the one load in
/// flight (still one download), while a rebuild after a FAILED load starts a
/// genuine retry — which is exactly what Retry Setup after an offline first run
/// depends on.
public struct SharedSpeechModel: Sendable {
    public let transcriber: WhisperKitTranscriber

    public init(transcriber: WhisperKitTranscriber) {
        self.transcriber = transcriber
    }

    /// The production model for `config`. `asrModel` and `keepWarmSeconds` are read
    /// here, once per launch — a hand edit of either applies at the next launch —
    /// unlike the recognition language, which is pushed live into the running
    /// transcriber.
    public init(config: Config) {
        transcriber = WhisperKitTranscriber(
            configuration: WhisperKitTranscriber.Configuration(
                keepWarmSeconds: config.keepWarmSeconds,
                language: config.language
            ),
            engine: WhisperKitEngine(model: config.asrModel),
            converter: WhisperSampleConverter(),
            clock: MonotonicClock()
        )
    }

    /// Starts this composition's preload, so the first dictation after it skips the
    /// cold load, and hands back the task the composition's model gate awaits. A
    /// failed preload completes the task too: `begin` then retries the load and
    /// surfaces the honest error instead of leaving the gate shut.
    public func startWarmUp() -> Task<Void, Never> {
        Task { [transcriber] in
            _ = try? await transcriber.warmUp()
        }
    }
}
