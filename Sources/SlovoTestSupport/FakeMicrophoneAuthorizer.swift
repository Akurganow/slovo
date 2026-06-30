import Foundation
import SlovoCore

/// A `MicrophoneAuthorizer` fake reporting exactly the authorization bit it was
/// constructed with.
public final class FakeMicrophoneAuthorizer: MicrophoneAuthorizer {
    private let authorized: Bool

    public init(authorized: Bool) {
        self.authorized = authorized
    }

    public func isMicrophoneAuthorized() async -> Bool {
        authorized
    }
}
