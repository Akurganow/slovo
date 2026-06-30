import Foundation

public enum OnboardingStep: Equatable, Sendable {
    case requestMicrophone
    case requestAccessibility
    case requestInputMonitoring
    case requestAnthropicKey
    case requestOpenAIKey
    case ready
}

public enum FirstRunFlow {
    public static func pendingSteps(
        permissions: PermissionStatus,
        cleanupProvider: CleanupProvider,
        hasAnthropicKey: Bool,
        hasOpenAIKey: Bool
    ) -> [OnboardingStep] {
        var steps: [OnboardingStep] = []
        if !permissions.microphone {
            steps.append(.requestMicrophone)
        }
        if !permissions.accessibility {
            steps.append(.requestAccessibility)
        }
        if !permissions.inputMonitoring {
            steps.append(.requestInputMonitoring)
        }
        if cleanupProvider == .anthropic, !hasAnthropicKey {
            steps.append(.requestAnthropicKey)
        } else if cleanupProvider == .openAI, !hasOpenAIKey {
            steps.append(.requestOpenAIKey)
        }
        return steps.isEmpty ? [.ready] : steps
    }
}
