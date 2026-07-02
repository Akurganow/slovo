/// Captures microphone audio and streams it as live §18.3 `AudioChunk`s.
///
/// `start()` must consult the `MicrophoneAuthorizer` FIRST and throw
/// `AudioCaptureError.microphoneDenied` without touching the engine when the mic
/// is not authorized. On success it returns an `AsyncStream<AudioChunk>` that
/// yields the tap's NATIVE buffers as they arrive. `stop()` ends capture and
/// finishes the stream so consumers' `for await` terminates.
public protocol AudioRecorder: Sendable {
    func start() async throws -> AsyncStream<AudioChunk>
    func stop() async
}
