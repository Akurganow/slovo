import AudioToolbox
import CoreAudio
import Foundation

/// Real CoreAudio implementation of `SystemAudioController` (spec §17, F1).
///
/// Mutes the current default output device via `kAudioDevicePropertyMute` when
/// that property is settable, falling back to driving the virtual master volume
/// to zero (and restoring the saved scalar) for devices that do not expose a
/// settable mute (e.g. some Bluetooth/USB DACs). The `AudioDeviceID` is pinned
/// at mute time so a device change mid-dictation cannot misdirect the restore.
///
/// L4: exercised on real hardware via the Epic-03 runbook, not in CI.
public struct CoreAudioOutputMute: SystemAudioController {
    /// Raised when CoreAudio reports a non-success status for a HAL call.
    public struct CoreAudioError: Error {
        public let status: OSStatus
        public let operation: String
    }

    public init() {}

    public func muteSystemOutput() throws -> PriorAudioState {
        let deviceID = try defaultOutputDeviceID()

        if try isMutePropertySettable(deviceID) {
            let wasAlreadyMuted = try currentMute(deviceID)
            if !wasAlreadyMuted {
                try setMute(deviceID, muted: true)
            }
            return PriorAudioState(
                deviceID: deviceID,
                method: .mute,
                wasAlreadyMuted: wasAlreadyMuted,
                priorVolumeScalar: nil
            )
        }

        // Fallback: drive the virtual master volume to zero, saving the prior
        // scalar so restore can put it back exactly.
        let priorScalar = try currentVirtualMasterVolume(deviceID)
        let wasAlreadyMuted = priorScalar == 0
        if !wasAlreadyMuted {
            try setVirtualMasterVolume(deviceID, scalar: 0)
        }
        return PriorAudioState(
            deviceID: deviceID,
            method: .virtualMasterVolume,
            wasAlreadyMuted: wasAlreadyMuted,
            priorVolumeScalar: priorScalar
        )
    }

    public func restoreSystemOutput(_ state: PriorAudioState) throws {
        // Never un-mute what the user had already silenced before we muted.
        guard !state.wasAlreadyMuted else { return }

        switch state.method {
        case .mute:
            try setMute(state.deviceID, muted: false)
        case .virtualMasterVolume:
            // Restore the exact scalar captured at mute time (default to full).
            try setVirtualMasterVolume(state.deviceID, scalar: state.priorVolumeScalar ?? 1)
        }
    }

    // MARK: - Device resolution

    private func defaultOutputDeviceID() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr else {
            throw CoreAudioError(status: status, operation: "getDefaultOutputDevice")
        }
        return deviceID
    }

    // MARK: - Mute property

    private func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func isMutePropertySettable(_ deviceID: AudioDeviceID) throws -> Bool {
        var address = muteAddress()
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(deviceID, &address, &settable)
        guard status == noErr else {
            throw CoreAudioError(status: status, operation: "isMuteSettable")
        }
        return settable.boolValue
    }

    private func currentMute(_ deviceID: AudioDeviceID) throws -> Bool {
        var address = muteAddress()
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        guard status == noErr else {
            throw CoreAudioError(status: status, operation: "getMute")
        }
        return muted != 0
    }

    private func setMute(_ deviceID: AudioDeviceID, muted: Bool) throws {
        var address = muteAddress()
        var value = UInt32(muted ? 1 : 0)
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
        guard status == noErr else {
            throw CoreAudioError(status: status, operation: "setMute")
        }
    }

    // MARK: - Virtual master volume fallback

    private func virtualMasterVolumeAddress() -> AudioObjectPropertyAddress {
        // The plan named `…_VirtualMasterVolume`, which the SDK deprecates in
        // favor of `…_VirtualMainVolume` (an identical numeric selector). Use the
        // non-deprecated name to keep the build warning-free; behavior is the same.
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func currentVirtualMasterVolume(_ deviceID: AudioDeviceID) throws -> Float {
        var address = virtualMasterVolumeAddress()
        var scalar = Float(0)
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &scalar)
        guard status == noErr else {
            throw CoreAudioError(status: status, operation: "getVirtualMasterVolume")
        }
        return scalar
    }

    private func setVirtualMasterVolume(_ deviceID: AudioDeviceID, scalar: Float) throws {
        var address = virtualMasterVolumeAddress()
        var value = scalar
        let size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
        guard status == noErr else {
            throw CoreAudioError(status: status, operation: "setVirtualMasterVolume")
        }
    }
}
