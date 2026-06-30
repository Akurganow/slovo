import Foundation

/// Reports whether the microphone is authorized, behind a narrow seam so the
/// "check authorization before touching the engine" rule is testable (least
/// privilege: this port exposes only the one bit the recorder needs).
public protocol MicrophoneAuthorizer: Sendable {
    func isMicrophoneAuthorized() async -> Bool
}
