/// Captures microphone audio and streams it as live `AudioChunk`s.
///
/// `start()` must consult the `MicrophoneAuthorizer` FIRST and throw
/// `AudioCaptureError.microphoneDenied` without touching the engine when the mic is
/// not authorized. On success it delivers every callback from the first captured
/// frame, so speech spoken while the speech model loads or a cue plays still reaches
/// recognition. `stop()` finishes the stream.
public protocol AudioRecorder: Sendable {
    func start() async throws -> AsyncStream<AudioChunk>
    func stop() async
}
