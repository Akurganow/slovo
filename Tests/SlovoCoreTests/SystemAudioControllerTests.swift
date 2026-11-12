import Testing

@testable import SlovoCore

// The restore decision: which device write undoes a mute, and with what value.
// Applying that write to the HAL is checked only on hardware.
@Suite("System audio restore decision")
struct SystemAudioControllerTests {

    /// Never un-mute what the user silenced: a device muted before dictation needs
    /// no restore write, whichever lever is in use.
    /// Stated sensitivity: delete the `wasAlreadyMuted` guard in `restoreWrite` → a write is returned for both methods → RED.
    @Test
    func restoreWriteIsNilWhenAlreadyMuted() {
        let muteLever = PriorAudioState(deviceID: 7, method: .mute, wasAlreadyMuted: true, priorVolumeScalar: nil)
        let volumeLever = PriorAudioState(deviceID: 7, method: .virtualMasterVolume, wasAlreadyMuted: true, priorVolumeScalar: 0)

        #expect(CoreAudioOutputMute.restoreWrite(for: muteLever) == nil)
        #expect(CoreAudioOutputMute.restoreWrite(for: volumeLever) == nil)
    }

    /// The mute lever is undone by unmuting the device pinned at mute time.
    /// Stated sensitivity: use another device ID, or `muted: true`, in the `.mute` arm → RED.
    @Test
    func restoreMuteUnmutesThePinnedDevice() {
        let state = PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)

        #expect(CoreAudioOutputMute.restoreWrite(for: state) == .mute(deviceID: 42, muted: false))
    }

    /// The volume fallback puts back the exact scalar saved at mute time.
    /// Stated sensitivity: ignore the saved scalar, or swap the method arms → RED.
    @Test
    func restoreVirtualVolumeReturnsThePriorScalar() {
        let state = PriorAudioState(deviceID: 42, method: .virtualMasterVolume, wasAlreadyMuted: false, priorVolumeScalar: 0.4)

        #expect(CoreAudioOutputMute.restoreWrite(for: state) == .volume(deviceID: 42, scalar: 0.4))
    }

    /// With no saved scalar, the volume fallback restores full volume.
    /// Stated sensitivity: change `?? 1` in `restoreWrite` → RED.
    @Test
    func restoreVirtualVolumeDefaultsToFullWhenScalarUnknown() {
        let state = PriorAudioState(deviceID: 42, method: .virtualMasterVolume, wasAlreadyMuted: false, priorVolumeScalar: nil)

        #expect(CoreAudioOutputMute.restoreWrite(for: state) == .volume(deviceID: 42, scalar: 1))
    }
}
