/// Mutes and restores system audio output, behind a seam so the mute/restore
/// behavior is unit-testable without touching CoreAudio (spec §17, F1).
public protocol SystemAudioController: Sendable {
    /// Captures and pins the current output device, mutes it, and returns the
    /// prior state to hand back to `restoreSystemOutput`.
    func muteSystemOutput() throws -> PriorAudioState

    /// Restores output on `state.deviceID`. A no-op when `state.wasAlreadyMuted`
    /// (never un-mute what the user had already silenced).
    func restoreSystemOutput(_ state: PriorAudioState) throws
}
