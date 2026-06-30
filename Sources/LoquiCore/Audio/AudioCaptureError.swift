import Foundation

/// Failure modes of microphone capture (spec §6, §11). Routed into the FSM as
/// `StageFailure.capture`, all surfacing the single honest `.microphoneUnavailable`
/// status.
public enum AudioCaptureError: Error, Equatable, Sendable {
    case microphoneDenied
    case engineStartFailed
    case formatUnavailable
    case conversionFailed
}
