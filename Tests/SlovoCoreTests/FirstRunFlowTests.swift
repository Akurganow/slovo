import Foundation
import Testing

import SlovoCore

// Determine the first-run steps from required setup permissions. Input Monitoring
// is diagnostic for hotkey recovery, not a generic first-run blocker.
@Suite("FirstRunFlow")
struct FirstRunFlowTests {
    @Test
    func readyWhenAllPermissionsAndKeyExist() {
        let steps = FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: true, inputMonitoring: true, microphone: true)
        )

        #expect(steps == [.ready])
    }

    /// Stated sensitivity: adding Input Monitoring back to generic setup, checking
    /// only Accessibility, or stopping after one missing permission changes this
    /// exact ordered list.
    @Test
    func reportsEveryMissingRequiredSetupPermission() {
        let steps = FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: false, inputMonitoring: false, microphone: false)
        )

        #expect(steps == [
            .requestMicrophone,
            .requestAccessibility,
        ])
    }

    @Test
    func requiredSetupPermissionBitsAreIndependent() {
        #expect(FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: true, inputMonitoring: true, microphone: false)
        ) == [.requestMicrophone])

        #expect(FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: false, inputMonitoring: true, microphone: true)
        ) == [.requestAccessibility])
    }

    /// Stated sensitivity: if Input Monitoring is treated as first-run setup
    /// again, this goes red and the app can show the generic setup alert forever
    /// even after Mic + Accessibility are granted.
    @Test
    func inputMonitoringAloneDoesNotBlockFirstRunSetup() {
        #expect(FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: true, inputMonitoring: false, microphone: true)
        ) == [.ready])
    }
}
