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
/// That warm-up task is minted PER composition rather than stored once. Each one
/// joins the transcriber's single-flight load, so a rebuild during a load still
/// means one download, and each retries a failed load by itself with growing
/// pauses until the model loads. The task succeeds only when the model has loaded
/// and fails only when cancelled, so the gate that awaits it opens only on a
/// loaded model.
public struct SharedSpeechModel: Sendable {
    public let transcriber: WhisperKitTranscriber
    private let sleep: @Sendable (Duration) async throws -> Void

    /// `sleep` waits out one retry pause and throws when its task is cancelled.
    init(
        transcriber: WhisperKitTranscriber,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.transcriber = transcriber
        self.sleep = sleep
    }

    /// The production model for `config`. `asrModel` is read here, once per launch —
    /// a hand edit of it applies at the next launch — unlike the recognition
    /// language, which is pushed live into the running transcriber.
    public init(config: Config) {
        self.init(
            transcriber: WhisperKitTranscriber(
                language: config.language,
                engine: WhisperKitEngine(model: config.asrModel),
                converter: WhisperSampleConverter()
            ),
            sleep: { try await Task.sleep(for: $0) }
        )
    }

    /// The wait before the next load attempt: 1 second after the first failure,
    /// doubling, capped at 60 seconds. `attempts` counts failures and is at least 1.
    static func retryPause(afterFailedAttempts attempts: Int) -> Duration {
        .seconds(min(60, 1 << min(attempts - 1, 6)))
    }

    /// Starts this composition's preload and hands back the task its model gate
    /// awaits. The task succeeds only when the model has loaded: a failed load
    /// (each one logs `asr.modelLoad state=failed`) is retried after a pause that
    /// doubles from one second up to a minute. Cancelling the task makes the pause
    /// throw, so the task fails and never reports a model it did not load.
    public func startWarmUp() -> Task<Void, any Error> {
        Task { [transcriber, sleep] in
            // Each pass ends the task or follows a failed attempt, so the count of
            // attempts made is the count of failures the pause is sized by.
            var attempts = 0
            while true {
                if attempts > 0 {
                    try await sleep(Self.retryPause(afterFailedAttempts: attempts))
                }
                attempts += 1
                if (try? await transcriber.warmUp()) != nil {
                    return
                }
            }
        }
    }
}
