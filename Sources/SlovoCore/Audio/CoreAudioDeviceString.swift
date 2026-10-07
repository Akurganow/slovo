import CoreAudio

/// Reads one CFString property of a device in global scope, such as its name
/// (`kAudioObjectPropertyName`) or its UID (`kAudioDevicePropertyDeviceUID`). The
/// HAL returns a string the caller releases, hence `takeRetainedValue()`. nil when
/// the read fails.
func readDeviceString(_ deviceID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
    guard status == noErr, let value else { return nil }
    return value.takeRetainedValue() as String
}
