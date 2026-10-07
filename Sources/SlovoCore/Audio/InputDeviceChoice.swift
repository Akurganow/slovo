/// An input device as Slovo stores and lists it: its CoreAudio UID, which stays
/// the same across reboots and reconnection, and its name.
public struct InputDevice: Codable, Hashable, Sendable {
    public let uid: String
    public let name: String

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

/// The present devices with at least one input channel, in HAL order, and the
/// system default input's UID.
public struct InputDevices: Equatable, Sendable {
    public var present: [InputDevice]
    public var systemDefaultUID: String?

    public init(present: [InputDevice] = [], systemDefaultUID: String? = nil) {
        self.present = present
        self.systemDefaultUID = systemDefaultUID
    }
}

/// The microphone preference decided against the devices present. The menu, the
/// Settings picker and the recorder all read it; none re-derives it.
public struct InputDeviceChoice: Equatable, Sendable {
    public let present: [InputDevice]
    /// nil is System Default. The present entry when the preference's UID is
    /// present. The stored device while it is absent.
    public let selection: InputDevice?
    /// The stored device while its UID is not present, else nil.
    public let absent: InputDevice?
    /// What the recorder assigns. nil leaves the system default.
    public let captureUID: String?
    public let fallbackLine: String?

    /// Matches by UID only, so a device renamed since it was chosen still matches.
    public static func derive(preference: InputDevice?, devices: InputDevices) -> InputDeviceChoice {
        guard let preference else {
            return InputDeviceChoice(present: devices.present, selection: nil, absent: nil, captureUID: nil, fallbackLine: nil)
        }
        if let match = devices.present.first(where: { $0.uid == preference.uid }) {
            return InputDeviceChoice(present: devices.present, selection: match, absent: nil, captureUID: match.uid, fallbackLine: nil)
        }
        let inUse = devices.present.first { $0.uid == devices.systemDefaultUID }?.name ?? "the system default"
        return InputDeviceChoice(
            present: devices.present,
            selection: preference,
            absent: preference,
            captureUID: nil,
            fallbackLine: "\(preference.name) is not available. Using \(inUse) instead."
        )
    }
}
