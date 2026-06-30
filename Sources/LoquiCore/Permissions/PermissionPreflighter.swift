import Foundation

/// The grant state of the three TCC permissions loqui needs (P22: preflight all
/// three, degrade if any is missing — not just Accessibility).
public struct PermissionStatus: Equatable, Sendable {
    public let accessibility: Bool
    public let inputMonitoring: Bool
    public let microphone: Bool

    /// `true` only when every required permission is granted.
    public var allGranted: Bool { accessibility && inputMonitoring && microphone }

    public init(accessibility: Bool, inputMonitoring: Bool, microphone: Bool) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.microphone = microphone
    }
}

/// Reports the current permission grant state, behind a seam so the
/// "preflight all three" rule is testable without real TCC.
public protocol PermissionPreflighter {
    func preflight() -> PermissionStatus
}
