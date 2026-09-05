import CoreFoundation

/// Reports whether macOS has assigned the fn key to a system action of its own.
/// A seam, so the menu model can be tested without the real preferences store.
public protocol FnKeyAssignmentReading {
    /// Whether macOS currently reacts to fn itself, so an fn push-to-talk hold is
    /// contested.
    var isFnKeySystemAssigned: Bool { get }
}

/// Reads the system's fn-key preference and classifies it.
public enum FnKeyAssignment {
    /// Whether the raw `AppleFnUsageType` preference names a real macOS action.
    ///
    /// `0` is the explicit "Do Nothing" setting and `nil` means the preference was
    /// unreadable; both must read as unassigned so a conflict is never invented.
    /// Every other value names some system action, so the classifier keys on
    /// "anything but Do Nothing" rather than on one enumerated action.
    public static func isAssigned(usageType: Int?) -> Bool {
        (usageType ?? 0) != 0
    }
}

/// Live `FnKeyAssignmentReading` backed by the macOS keyboard preference.
///
/// A thin adapter over `CFPreferencesCopyAppValue`, deliberately untested: it only
/// fetches the raw value and hands it to `FnKeyAssignment.isAssigned(usageType:)`,
/// which carries the whole rule.
public struct SystemFnKeyAssignmentReader: FnKeyAssignmentReading {
    public init() {}

    public var isFnKeySystemAssigned: Bool {
        // The "Press 🌐 key to" choice lives in another application's preference
        // domain, so CFPreferences is the way in — this app's UserDefaults cannot
        // see it.
        let usageType = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString) as? Int
        return FnKeyAssignment.isAssigned(usageType: usageType)
    }
}
