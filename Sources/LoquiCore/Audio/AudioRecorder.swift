import Foundation

/// Captures microphone audio and returns it as a §18.3 `AudioBuffer`.
///
/// `start()` must consult the `MicrophoneAuthorizer` FIRST and throw
/// `AudioCaptureError.microphoneDenied` without touching the engine when the mic
/// is not authorized. `stop()` returns the captured audio as 16 kHz mono Float.
public protocol AudioRecorder: Sendable {
    func start() async throws
    func stop() async throws -> AudioBuffer
}
