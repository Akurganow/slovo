import Foundation
import Testing

import SlovoCore

// Epic 09b — AC-8 CI half: determine the first-run steps from permission/key
// state. Real TCC prompts, Settings deep-links, and key entry UI are L4.
@Suite("Epic 09b FirstRunFlow")
struct FirstRunFlowTests {
    @Test
    func readyWhenAllPermissionsAndKeyExist() {
        let steps = FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: true, inputMonitoring: true, microphone: true),
            cleanupProvider: .anthropic,
            hasAnthropicKey: true,
            hasOpenAIKey: false
        )

        #expect(steps == [.ready])
    }

    /// Stated sensitivity: checking only Accessibility or stopping after one
    /// missing permission drops required steps and this exact ordered list fails.
    @Test
    func reportsEveryMissingPermissionBeforeKey() {
        let steps = FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: false, inputMonitoring: false, microphone: false),
            cleanupProvider: .anthropic,
            hasAnthropicKey: false,
            hasOpenAIKey: false
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
            cleanupProvider: .anthropic,
            hasAnthropicKey: false,
            hasOpenAIKey: false
        )

        #expect(steps == [.requestAnthropicKey])
    }

    /// Stated sensitivity: keep first-run hard-coded to the Anthropic key -> an
    /// OpenAI-selected cleanup config asks for the wrong credential.
    @Test
    func openAIProviderRequiresOpenAIKeyOnly() {
        let steps = FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: true, inputMonitoring: true, microphone: true),
            cleanupProvider: .openAI,
            hasAnthropicKey: true,
            hasOpenAIKey: false
        )

        #expect(steps == [.requestOpenAIKey])
    }

    @Test
    func eachPermissionBitIsIndependent() {
        #expect(FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: true, inputMonitoring: true, microphone: false),
            cleanupProvider: .anthropic,
            hasAnthropicKey: true,
            hasOpenAIKey: false
        ) == [.requestMicrophone])

        #expect(FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: false, inputMonitoring: true, microphone: true),
            cleanupProvider: .anthropic,
            hasAnthropicKey: true,
            hasOpenAIKey: false
        ) == [.requestAccessibility])

        #expect(FirstRunFlow.pendingSteps(
            permissions: PermissionStatus(accessibility: true, inputMonitoring: false, microphone: true),
            cleanupProvider: .anthropic,
            hasAnthropicKey: true,
            hasOpenAIKey: false
        ) == [.requestInputMonitoring])
    }
}
