import Foundation
import Testing

import SlovoCore

// Epic 09b — AC-8 CI half: determine the first-run steps from permission state.
// Cleanup credentials are optional because provider failures degrade to raw
// transcript insertion. Real TCC prompts and Settings deep-links are L4.
@Suite("Epic 09b FirstRunFlow")
struct FirstRunFlowTests {
    @Test
    func readyWhenAllPermissionsAndKeyExist() {
        let steps = FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: true, inputMonitoring: true, microphone: true)
        )

        #expect(steps == [.ready])
    }

    /// Stated sensitivity: checking only Accessibility or stopping after one
    /// missing permission drops required steps and this exact ordered list fails.
    @Test
    func reportsEveryMissingPermission() {
        let steps = FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: false, inputMonitoring: false, microphone: false)
        )

        #expect(steps == [
            .requestMicrophone,
            .requestAccessibility,
            .requestInputMonitoring,
        ])
    }

    @Test
    func eachPermissionBitIsIndependent() {
        #expect(FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: true, inputMonitoring: true, microphone: false)
        ) == [.requestMicrophone])

        #expect(FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: false, inputMonitoring: true, microphone: true)
        ) == [.requestAccessibility])

        #expect(FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: true, inputMonitoring: false, microphone: true)
        ) == [.requestInputMonitoring])
    }
}
