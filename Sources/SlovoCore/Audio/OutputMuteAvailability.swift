/// Whether Slovo can mute the default output device, and why not. The dropdown's
/// mute item and the Settings toggle both read it; neither re-derives it.
public enum OutputMuteAvailability: Equatable, Sendable {
    case available
    case unavailable(deviceName: String)

    public var isToggleEnabled: Bool { self == .available }

    /// The reason shown in Settings and as the menu item's tooltip; nil while available.
    public var unavailableHint: String? {
        guard case .unavailable(let deviceName) = self else { return nil }
        return "\(deviceName) has no volume control macOS can set."
    }

    /// The one decision: unavailable only on positive evidence that neither lever
    /// exists. An unreadable name falls back to a neutral subject.
    public static func derive(
        hasSettableMute: Bool,
        hasSettableVolume: Bool,
        deviceName: String?
    ) -> OutputMuteAvailability {
        guard !hasSettableMute, !hasSettableVolume else { return .available }
        return .unavailable(deviceName: deviceName ?? "This output device")
    }
}
