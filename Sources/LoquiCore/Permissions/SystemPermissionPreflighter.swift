import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation

/// Real TCC implementation of `PermissionPreflighter` (P22): checks all three
/// permissions independently so loqui degrades gracefully if any is missing,
/// rather than assuming Accessibility implies the rest.
///
/// L4: the grant prompts are exercised on a clean machine via the runbook.
public struct SystemPermissionPreflighter: PermissionPreflighter {
    public init() {}

    public func preflight() -> PermissionStatus {
        PermissionStatus(
            accessibility: isAccessibilityTrusted(),
            inputMonitoring: isInputMonitoringGranted(),
            microphone: isMicrophoneAuthorized()
        )
    }

    private func isAccessibilityTrusted() -> Bool {
        // Query only — never passes the prompt option here (preflight must not
        // surface a dialog as a side effect).
        AXIsProcessTrustedWithOptions(nil)
    }

    private func isInputMonitoringGranted() -> Bool {
        CGPreflightListenEventAccess()
    }

    private func isMicrophoneAuthorized() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}

/// The production `MicrophoneAuthorizer` conformer, so the live
/// `AVAudioEngineRecorder` can be constructed with a real authorizer (the narrow
/// seam previously had only a test fake). L4: not exercised in CI.
extension SystemPermissionPreflighter: MicrophoneAuthorizer {
    public func isMicrophoneAuthorized() async -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}
