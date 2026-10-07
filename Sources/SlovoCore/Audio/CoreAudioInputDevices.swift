import CoreAudio

/// Reads the input side of the CoreAudio HAL. Stateless: every call reads the HAL
/// afresh.
///
/// Exercised on real hardware, not in CI.
public struct CoreAudioInputDevices: Sendable {
    public init() {}

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
}
