import Foundation
import Testing

import LoquiCore

// Epic 09b — AC-8 CI half: determine the first-run steps from permission/key
// state. Real TCC prompts, Settings deep-links, and key entry UI are L4.
@Suite("Epic 09b FirstRunFlow")
struct FirstRunFlowTests {
    @Test
    func readyWhenAllPermissionsAndKeyExist() {
        let steps = FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: true, inputMonitoring: true, microphone: true),
            hasKey: true
        )

        #expect(steps == [.ready])
    }

    /// Stated sensitivity: checking only Accessibility or stopping after one
    /// missing permission drops required steps and this exact ordered list fails.
    @Test
    func reportsEveryMissingPermissionBeforeKey() {
        let steps = FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: false, inputMonitoring: false, microphone: false),
            hasKey: false
        )

        #expect(steps == [
            .requestMicrophone,
            .requestAccessibility,
            .requestInputMonitoring,
            .requestAnthropicKey,
        ])
    }

    @Test
    func keyStepAppearsAfterGrantedPermissions() {
        let steps = FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: true, inputMonitoring: true, microphone: true),
            hasKey: false
        )

        #expect(steps == [.requestAnthropicKey])
    }

    @Test
    func eachPermissionBitIsIndependent() {
        #expect(FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: true, inputMonitoring: true, microphone: false),
            hasKey: true
        ) == [.requestMicrophone])

        #expect(FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: false, inputMonitoring: true, microphone: true),
            hasKey: true
        ) == [.requestAccessibility])

        #expect(FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: true, inputMonitoring: false, microphone: true),
            hasKey: true
        ) == [.requestInputMonitoring])
    }
}
