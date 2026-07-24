import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Restore targets the EXACT pinned device, and wasAlreadyMuted ⇒ restore is a
// no-op.
//
// Contract under test (the seam lives in `Sources/SlovoCore/Audio/`, the fake in
// `Sources/SlovoTestSupport/`):
//
//     struct PriorAudioState { deviceID; method; wasAlreadyMuted; priorVolumeScalar }
//     protocol SystemAudioController {
//         func muteSystemOutput() throws -> PriorAudioState
//         func restoreSystemOutput(_ state: PriorAudioState) throws
//     }
@Suite("System audio controller")
struct SystemAudioControllerTests {

    /// AirPods-connect-mid-dictation: restore must target the device
    /// PINNED at mute time (`state.deviceID`), never the then-current default.
    /// Stated sensitivity: make restore target the current default (id 99) → the
    /// recorded device ≠ 42 → RED.
    @Test
    func restoreTargetsThePinnedDevice() throws {
        let pinned = PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
        let controller = FakeSystemAudioController(muteReturns: pinned)

        let state = try controller.muteSystemOutput()
        try controller.restoreSystemOutput(state)

        #expect(controller.restoredDeviceIDs == [42],
                "restore must target the pinned deviceID 42, got \(controller.restoredDeviceIDs)")
    }

    /// Never un-mute what the user silenced: when the device was
    /// ALREADY muted at mute time, restore performs NO device write.
    /// Stated sensitivity: make restore always un-mute regardless of
    /// `wasAlreadyMuted` → a device write is recorded for the already-muted case
    /// → RED.
    @Test
    func restoreIsNoOpWhenWasAlreadyMuted() throws {
        let alreadyMuted = PriorAudioState(deviceID: 7, method: .mute, wasAlreadyMuted: true, priorVolumeScalar: nil)
        let controller = FakeSystemAudioController(muteReturns: alreadyMuted)

        let state = try controller.muteSystemOutput()
        try controller.restoreSystemOutput(state)

        #expect(controller.restoreDeviceWrites == [false],
                "restore must be a no-op (no device write) when wasAlreadyMuted, got writes=\(controller.restoreDeviceWrites)")
    }
}
