import CoreAudio

/// Reads the input side of the CoreAudio HAL. Stateless: every call reads the HAL
/// afresh.
///
/// Exercised on real hardware, not in CI.
public struct CoreAudioInputDevices: Sendable {
    public init() {}

    /// The present devices with at least one input channel and not private to one
    /// process, in HAL order, and the system default input's UID. A device whose UID
    /// or name cannot be read is not listed.
    public func inputDevices() -> InputDevices {
        let present = deviceIDs().compactMap { deviceID -> InputDevice? in
            guard inputChannelCount(of: deviceID) > 0,
                  !isPrivateAggregate(deviceID),
                  let uid = readDeviceString(deviceID, selector: kAudioDevicePropertyDeviceUID),
                  let name = readDeviceString(deviceID, selector: kAudioObjectPropertyName)
            else { return nil }
            return InputDevice(uid: uid, name: name)
        }
        let systemDefaultUID = defaultInputDeviceID().flatMap { readDeviceString($0, selector: kAudioDevicePropertyDeviceUID) }
        return InputDevices(present: present, systemDefaultUID: systemDefaultUID)
    }

    /// The device a UID names now, or nil when no present device has it. The HAL
    /// answers an unknown UID with `kAudioObjectUnknown`, not an error.
    func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafePointer(to: uid as CFString) { qualifier in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), qualifier, &size, &deviceID
            )
        }
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    /// Calls `handler` with a fresh reading after each change of the device list or
    /// of the system default input, and returns the labels of the registrations that
    /// failed. One registration per address, so a registration that succeeded stays.
    /// The HAL keeps a block until a matching remove, and this type never removes
    /// it, so call it once per process. The blocks run on the main queue, so the
    /// read and the handler's store write share one turn.
    @preconcurrency // required by the strict SwiftLint rule incompatible_concurrency_annotation
    @MainActor
    public func observeInputDevices(_ handler: @escaping @MainActor (InputDevices) -> Void) -> [String] {
        let addresses = [
            ("device list", kAudioHardwarePropertyDevices),
            ("default input", kAudioHardwarePropertyDefaultInputDevice),
        ]
        return addresses.compactMap { label, selector in
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            // The changed-address list is ignored: either change calls for one re-read.
            let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
                let devices = inputDevices()
                MainActor.assumeIsolated { handler(devices) }
            }
            return status == noErr ? nil : label
        }
    }

    /// The system default input device, or nil when the HAL names none.
    func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    /// The device's input channels for stereo, 1-based, left then right, or nil when
    /// the HAL cannot read them.
    func preferredStereoChannels(of deviceID: AudioDeviceID) -> [Int]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var channels = [UInt32](repeating: 0, count: 2)
        let expectedSize = UInt32(MemoryLayout<UInt32>.size * channels.count)
        var size = expectedSize
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &channels)
        guard status == noErr, size == expectedSize else { return nil }
        return channels.map(Int.init)
    }

    private func deviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var deviceIDs = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &deviceIDs) == noErr else { return [] }
        return Array(deviceIDs.prefix(Int(size) / MemoryLayout<AudioDeviceID>.size))
    }

    /// Whether the device is an aggregate private to the process that created it,
    /// such as the one the HAL makes for a process that opens the default input.
    /// false when unreadable.
    private func isPrivateAggregate(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport) == noErr,
              transport == kAudioDeviceTransportTypeAggregate else { return false }
        address.mSelector = kAudioAggregateDevicePropertyComposition
        var composition: Unmanaged<CFDictionary>?
        size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &composition) == noErr,
              let composition else { return false }
        // The HAL returns a dictionary the caller releases.
        let isPrivate = (composition.takeRetainedValue() as? [String: Any])?[kAudioAggregateDeviceIsPrivateKey] as? Int
        return (isPrivate ?? 0) != 0
    }

    /// The device's input channels across all its input streams; 0 when unreadable.
    private func inputChannelCount(of deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
