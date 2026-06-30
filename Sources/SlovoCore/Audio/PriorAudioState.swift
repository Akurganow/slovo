import Foundation

/// The system-audio state captured at mute time, used to restore at key-up
/// (spec §17, P28). Pinning the device means an output change mid-dictation
/// (e.g. AirPods connecting) cannot misdirect the restore.
public struct PriorAudioState: Equatable, Sendable {
    /// Which lever was used to silence output, so restore uses the same one.
    public enum Method: Equatable, Sendable {
        case mute
        case virtualMasterVolume
    }

    /// The `AudioDeviceID` pinned at mute time — the device restore must target.
    public let deviceID: UInt32
    public let method: Method
    /// `true` ⇒ restore is a no-op (never un-mute what the user already silenced).
    public let wasAlreadyMuted: Bool
    /// The volume scalar to restore for `.virtualMasterVolume`; `nil` for `.mute`.
    public let priorVolumeScalar: Float?

    public init(deviceID: UInt32, method: Method, wasAlreadyMuted: Bool, priorVolumeScalar: Float?) {
        self.deviceID = deviceID
        self.method = method
        self.wasAlreadyMuted = wasAlreadyMuted
        self.priorVolumeScalar = priorVolumeScalar
    }
}
