/// Captures microphone audio and streams it as live `AudioChunk`s.
///
/// `start()` must consult the `MicrophoneAuthorizer` FIRST and throw
/// `AudioCaptureError.microphoneDenied` without touching the engine when the mic is
/// not authorized. On success it delivers from the first captured frame, so speech
/// spoken while the speech model loads still reaches recognition.
///
/// `suspendDelivery()`/`resumeDelivery()` bracket the readiness cue's playback — the
/// interval that must not reach recognition — at the cost of up to one callback
/// around it. `stop()` finishes the stream.
public protocol AudioRecorder: Sendable {
    func start() async throws -> AsyncStream<AudioChunk>
    func suspendDelivery()
    func resumeDelivery()
    func stop() async
}
