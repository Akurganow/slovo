import AudioToolbox
import CoreAudio
import os

/// Real CoreAudio implementation of `SystemAudioController`.
///
/// Mutes the current default output device via `kAudioDevicePropertyMute` when
/// that property is settable, falling back to driving the virtual master volume
/// to zero (and restoring the saved scalar) for devices that do not expose a
/// settable mute (e.g. some Bluetooth/USB DACs). The `AudioDeviceID` is pinned
/// at mute time so a device change mid-dictation cannot misdirect the restore.
/// A device with neither lever makes `muteSystemOutput` throw `NoOutputControl`.
///
/// `muteLever` is the one decision of which lever a device has: `muteSystemOutput`
/// and the availability read both call it.
///
/// The HAL calls run only on real hardware; CI tests the pure decisions,
/// `muteLever(hasSettableMute:hasSettableVolume:)` and `restoreWrite(for:)`.
public struct CoreAudioOutputMute: SystemAudioController {
    /// A HAL call that returned an error status. The helpers throw it and never log:
    /// the availability probe reads through them, where a failure is an expected
    /// answer. `muteSystemOutput` logs it.
    private struct HALFailure: Error {
        let call: HALCall
        let status: OSStatus
    }

    /// Thrown by `muteSystemOutput` for a device with no settable control. That is not
    /// a failure, so it is never logged.
    private struct NoOutputControl: Error {}

    /// The device write a restore issues.
    enum OutputWrite: Equatable {
        case mute(deviceID: AudioDeviceID, muted: Bool)
        case volume(deviceID: AudioDeviceID, scalar: Float)
    }

    private enum HALCall {
        case getDefaultDevice
        case isSettable
        case getMute
        case setMute
        case getVolume
        case setVolume
    }

    private static let diagnosticLog = Logger(subsystem: "com.slovo.app", category: "dictation")

    public init() {}

    /// Reads whether the default output device has a mute or volume control macOS
    /// can set. An unreadable device or check reports `.available`, which keeps
    /// today's behaviour: only positive absence of both levers disables the switch.
    public func outputMuteAvailability() -> OutputMuteAvailability {
        guard let deviceID = try? defaultOutputDeviceID(), deviceID != kAudioObjectUnknown else {
            return .available
        }
        let lever = Self.muteLever(
            hasSettableMute: (try? isPropertySettable(deviceID, muteAddress())) ?? true,
            hasSettableVolume: (try? isPropertySettable(deviceID, virtualMasterVolumeAddress())) ?? true
        )
        return .derive(lever: lever, deviceName: readDeviceString(deviceID, selector: kAudioObjectPropertyName))
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
        let state: PriorAudioState?
        do {
            state = try muteDefaultOutput()
        } catch {
            switch error.call {
            case .getDefaultDevice:
                Self.diagnosticLog.error("output.mute failed step=getDefaultDevice status=\(error.status)")
            case .isSettable:
                Self.diagnosticLog.error("output.mute failed step=isSettable status=\(error.status)")
            case .getMute:
                Self.diagnosticLog.error("output.mute failed step=getMute status=\(error.status)")
            case .setMute:
                Self.diagnosticLog.error("output.mute failed step=setMute status=\(error.status)")
            case .getVolume:
                Self.diagnosticLog.error("output.mute failed step=getVolume status=\(error.status)")
            case .setVolume:
                Self.diagnosticLog.error("output.mute failed step=setVolume status=\(error.status)")
            }
            throw error
        }
        guard let state else { throw NoOutputControl() }
        return state
    }

    private func muteDefaultOutput() throws(HALFailure) -> PriorAudioState? {
        let deviceID = try defaultOutputDeviceID()
        let hasSettableMute = try isPropertySettable(deviceID, muteAddress())
        // A settable mute already decides the lever; a failing volume check must not fail a mute that works.
        var hasSettableVolume = false
        if !hasSettableMute {
            hasSettableVolume = try isPropertySettable(deviceID, virtualMasterVolumeAddress())
        }
        let lever = Self.muteLever(hasSettableMute: hasSettableMute, hasSettableVolume: hasSettableVolume)

        switch lever {
        case .mute:
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
        case .virtualMasterVolume:
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
        case nil:
            return nil
        }
    }

    public func restoreSystemOutput(_ state: PriorAudioState) throws {
        guard let write = Self.restoreWrite(for: state) else { return }
        do {
            switch write {
            case .mute(let deviceID, let muted):
                try setMute(deviceID, muted: muted)
            case .volume(let deviceID, let scalar):
                try setVirtualMasterVolume(deviceID, scalar: scalar)
            }
        } catch {
            Self.diagnosticLog.error("output.restore failed status=\(error.status)")
            throw error
        }
    }

    /// The one decision of which lever a device has: a settable mute, else a settable
    /// volume, else nil. `muteDefaultOutput()` and `outputMuteAvailability()` both call it,
    /// so the probe and the mute path cannot disagree.
    static func muteLever(hasSettableMute: Bool, hasSettableVolume: Bool) -> PriorAudioState.Method? {
        if hasSettableMute { return .mute }
        return hasSettableVolume ? .virtualMasterVolume : nil
    }

    /// The write that undoes a mute, or nil when there is nothing to undo.
    static func restoreWrite(for state: PriorAudioState) -> OutputWrite? {
        // Never un-mute what the user had already silenced before we muted.
        guard !state.wasAlreadyMuted else { return nil }

        switch state.method {
        case .mute:
            return .mute(deviceID: state.deviceID, muted: false)
        case .virtualMasterVolume:
            // Restore the exact scalar captured at mute time (default to full).
            return .volume(deviceID: state.deviceID, scalar: state.priorVolumeScalar ?? 1)
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

    private func defaultOutputDeviceID() throws(HALFailure) -> AudioDeviceID {
        var address = defaultOutputAddress()
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr else {
            throw HALFailure(call: .getDefaultDevice, status: status)
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
    private func isPropertySettable(
        _ deviceID: AudioDeviceID,
        _ address: AudioObjectPropertyAddress
    ) throws(HALFailure) -> Bool {
        var address = address
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(deviceID, &address, &settable)
        guard status == noErr else {
            throw HALFailure(call: .isSettable, status: status)
        }
        return settable.boolValue
    }

    private func currentMute(_ deviceID: AudioDeviceID) throws(HALFailure) -> Bool {
        var address = muteAddress()
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        guard status == noErr else {
            throw HALFailure(call: .getMute, status: status)
        }
        return muted != 0
    }

    private func setMute(_ deviceID: AudioDeviceID, muted: Bool) throws(HALFailure) {
        var address = muteAddress()
        var value = UInt32(muted ? 1 : 0)
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
        guard status == noErr else {
            throw HALFailure(call: .setMute, status: status)
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

    private func currentVirtualMasterVolume(_ deviceID: AudioDeviceID) throws(HALFailure) -> Float {
        var address = virtualMasterVolumeAddress()
        var scalar = Float(0)
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &scalar)
        guard status == noErr else {
            throw HALFailure(call: .getVolume, status: status)
        }
        return scalar
    }

    private func setVirtualMasterVolume(_ deviceID: AudioDeviceID, scalar: Float) throws(HALFailure) {
        var address = virtualMasterVolumeAddress()
        var value = scalar
        let size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
        guard status == noErr else {
            throw HALFailure(call: .setVolume, status: status)
        }
    }
}
