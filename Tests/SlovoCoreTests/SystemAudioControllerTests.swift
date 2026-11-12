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

    /// A device with neither a settable mute nor a settable volume has no lever. The mute path
    /// maps this nil to a throw that is never logged, so the failure log switch cannot receive it.
    /// Stated sensitivity: return `.virtualMasterVolume` instead of nil when neither is settable → RED.
    @Test
    func muteLeverIsNilWithoutAnySettableControl() {
        #expect(CoreAudioOutputMute.muteLever(hasSettableMute: false, hasSettableVolume: false) == nil)
    }

    /// A settable mute wins, whether or not the volume is settable.
    /// Stated sensitivity: prefer the volume when both are settable, or drop the mute arm → RED.
    @Test
    func muteLeverPrefersASettableMute() {
        #expect(CoreAudioOutputMute.muteLever(hasSettableMute: true, hasSettableVolume: false) == .mute)
        #expect(CoreAudioOutputMute.muteLever(hasSettableMute: true, hasSettableVolume: true) == .mute)
    }

    /// Without a settable mute, a settable volume is the lever.
    /// Stated sensitivity: return nil, or `.mute`, for a settable volume alone → RED.
    @Test
    func muteLeverFallsBackToASettableVolume() {
        #expect(CoreAudioOutputMute.muteLever(hasSettableMute: false, hasSettableVolume: true) == .virtualMasterVolume)
    }
}
