import Foundation
import SlovoCore

/// A `PermissionPreflighter` fake that reports exactly the three grant bits it
/// was constructed with — no permission is silently forced.
public final class FakePermissionPreflighter: PermissionPreflighter {
    private let accessibility: Bool
    private let inputMonitoring: Bool
    private let microphone: Bool

    public init(accessibility: Bool, inputMonitoring: Bool, microphone: Bool) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.microphone = microphone
    }

    public func preflight() -> PermissionStatus {
        PermissionStatus(
            accessibility: accessibility,
            inputMonitoring: inputMonitoring,
            microphone: microphone
        )
    }
}
