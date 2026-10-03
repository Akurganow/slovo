import AudioToolbox
import CoreAudio

/// Real CoreAudio implementation of `SystemAudioController`.
///
/// Mutes the current default output device via `kAudioDevicePropertyMute` when
/// that property is settable, falling back to driving the virtual master volume
/// to zero (and restoring the saved scalar) for devices that do not expose a
/// settable mute (e.g. some Bluetooth/USB DACs). The `AudioDeviceID` is pinned
/// at mute time so a device change mid-dictation cannot misdirect the restore.
///
/// The availability read checks the same two levers `muteSystemOutput` uses, in
/// the same way: a settable mute, else a settable virtual main volume.
///
/// Exercised on real hardware, not in CI.
public struct CoreAudioOutputMute: SystemAudioController {
    /// Raised when CoreAudio reports a non-success status for a HAL call.
    public struct CoreAudioError: Error {
        public let status: OSStatus
        public let operation: String
    }

    public init() {}

    /// Reads whether the default output device has a mute or volume control macOS
    /// can set. An unreadable device or check reports `.available`, which keeps
    /// today's behaviour: only positive absence of both levers disables the switch.
    public func outputMuteAvailability() -> OutputMuteAvailability {
        guard let deviceID = try? defaultOutputDeviceID(), deviceID != kAudioObjectUnknown else {
            return .available
        }
        return .derive(
            hasSettableMute: (try? isPropertySettable(deviceID, muteAddress())) ?? true,
            hasSettableVolume: (try? isPropertySettable(deviceID, virtualMasterVolumeAddress())) ?? true,
            deviceName: try? deviceName(deviceID)
        )
    }

    /// Calls `handler` with a fresh reading after every change of the default output
    /// device. The HAL keeps the block until a matching remove, and this type never
    /// removes it, so call it once per process. The block runs on the main queue, so
    /// the read and the handler's store write share one turn.
    @preconcurrency // required by the strict SwiftLint rule incompatible_concurrency_annotation
    @MainActor
    public func observeOutputMuteAvailability(
        _ handler: @escaping @MainActor (OutputMuteAvailability) -> Void
    ) -> OSStatus {
        var address = defaultOutputAddress()
        // The changed-address list is ignored: with one registered property, a
        // re-read is always right.
        return AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
            let availability = outputMuteAvailability()
            MainActor.assumeIsolated { handler(availability) }
        }
    }

    public func muteSystemOutput() throws -> PriorAudioState {
        let deviceID = try defaultOutputDeviceID()

        if try isPropertySettable(deviceID, muteAddress()) {
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

    private func defaultOutputAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// The device's display name. `kAudioObjectPropertyName` returns a CFString the
    /// caller releases, hence `takeRetainedValue()`.
    private func deviceName(_ deviceID: AudioDeviceID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr, let name else {
            throw CoreAudioError(status: status, operation: "getDeviceName")
        }
        return name.takeRetainedValue() as String
    }

    private func defaultOutputDeviceID() throws -> AudioDeviceID {
        var address = defaultOutputAddress()
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

    /// A lever counts only when the property exists AND is settable: a present but
    /// read-only volume would make the fallback's set throw.
    private func isPropertySettable(_ deviceID: AudioDeviceID, _ address: AudioObjectPropertyAddress) throws -> Bool {
        var address = address
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(deviceID, &address, &settable)
        guard status == noErr else {
            throw CoreAudioError(status: status, operation: "isPropertySettable")
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
        // The SDK deprecates `…_VirtualMasterVolume` in favor of
        // `…_VirtualMainVolume` (an identical numeric selector). Use the
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
