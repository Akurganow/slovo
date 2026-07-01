/// The grant state of the TCC permissions Slovo can need across setup, hotkey
/// capture, and text insertion.
public struct PermissionStatus: Equatable, Sendable {
    public let accessibility: Bool
    public let inputMonitoring: Bool
    public let microphone: Bool

    /// `true` only when every tracked permission is granted. First-run setup
    /// readiness is deliberately narrower and lives in `FirstRunFlow`.
    public var allGranted: Bool { accessibility && inputMonitoring && microphone }

    public init(accessibility: Bool, inputMonitoring: Bool, microphone: Bool) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.microphone = microphone
    }
}

/// Reports the current permission grant state behind a seam so permission
/// decisions are testable without real TCC.
public protocol PermissionPreflighter {
    func preflight() -> PermissionStatus
}

public enum SystemPermission: Equatable, Sendable {
    case microphone
    case accessibility
    case inputMonitoring
}

/// Requests one system permission.
public protocol PermissionRequester: Sendable {
    func request(_ permission: SystemPermission) async -> Bool
}
