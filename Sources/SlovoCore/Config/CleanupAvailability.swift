/// The effective cleanup state and its cause — the app layer's single source of
/// truth (spec 2026-07-22, amendment A5). Menu, Settings, the glyph layer, and
/// the dictation settings all consume this; the "off because toggled" vs "off
/// because no key" distinction is derived exactly once.
public enum CleanupAvailability: Equatable, Sendable {
    case on
    case offByChoice
    case offNoKey

    /// `preference` is the stored `Config.cleanupEnabled`; `providerReady` is
    /// whether the chosen provider can run now (for OpenRouter, the Keychain
    /// fact). An unready provider wins: without one, cleanup cannot run
    /// regardless of preference, and the preference itself is never rewritten.
    static func derive(preference: Bool, providerReady: Bool) -> CleanupAvailability {
        guard providerReady else { return .offNoKey }
        return preference ? .on : .offByChoice
    }

    public var isOn: Bool { self == .on }

    /// Whether the user can flip the toggle: a control that cannot take effect
    /// (no key) is shown off AND disabled, never flippable.
    public var isToggleEnabled: Bool { self != .offNoKey }

    /// The Settings status line under the master toggle; nil while cleanup is on.
    public var settingsStatusLine: String? {
        switch self {
        case .on:
            return nil
        case .offByChoice:
            return "Cleanup is off."
        case .offNoKey:
            return "Cleanup is off — add an OpenRouter API key to enable it."
        }
    }
}
