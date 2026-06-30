import Foundation

public enum OnboardingStep: Equatable, Sendable {
    case requestMicrophone
    case requestAccessibility
    case requestInputMonitoring
    case requestAnthropicKey
    case ready
}

public enum FirstRunFlow {
    public static func pendingSteps(permissions: PermissionStatus, hasKey: Bool) -> [OnboardingStep] {
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
        if !hasKey {
            steps.append(.requestAnthropicKey)
        }
        return steps.isEmpty ? [.ready] : steps
    }
}
