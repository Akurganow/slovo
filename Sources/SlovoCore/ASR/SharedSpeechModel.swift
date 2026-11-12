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
/// pauses until the model loads. The gate that awaits the task therefore opens
/// only on a loaded model.
public struct SharedSpeechModel: Sendable {
    public let transcriber: WhisperKitTranscriber
    private let pause: @Sendable (_ failedAttempts: Int) async -> Void

    public init(
        transcriber: WhisperKitTranscriber,
        pause: @escaping @Sendable (_ failedAttempts: Int) async -> Void
    ) {
        self.transcriber = transcriber
        self.pause = pause
    }

    /// The production model for `config`. `asrModel` is read here, once per launch —
    /// a hand edit of it applies at the next launch — unlike the recognition
    /// language, which is pushed live into the running transcriber.
    public init(config: Config) {
        pause = { try? await Task.sleep(for: SharedSpeechModel.retryPause(afterFailedAttempts: $0)) }
        transcriber = WhisperKitTranscriber(
            configuration: WhisperKitTranscriber.Configuration(
                language: config.language
            ),
            engine: WhisperKitEngine(model: config.asrModel),
            converter: WhisperSampleConverter()
        )
    }

    /// The wait before the next load attempt: 1 second after the first failure,
    /// doubling, capped at 60 seconds.
    static func retryPause(afterFailedAttempts attempts: Int) -> Duration {
        .seconds(min(60, 1 << min(max(attempts - 1, 0), 6)))
    }

    /// Starts this composition's preload and hands back the task its model gate
    /// awaits. The task completes only when the model has loaded: a failed load
    /// (each one logs `asr.modelLoad state=failed`) is retried after a pause that
    /// doubles from one second up to a minute.
    public func startWarmUp() -> Task<Void, Never> {
        Task { [transcriber, pause] in
            var failedAttempts = 0
            while true {
                do {
                    _ = try await transcriber.warmUp()
                    return
                } catch {
                    failedAttempts += 1
                    await pause(failedAttempts)
                }
            }
        }
    }
}
