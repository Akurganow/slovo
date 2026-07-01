public enum OnboardingStep: Equatable, Sendable {
    case requestMicrophone
    case requestAccessibility
    case requestInputMonitoring
    case ready
}

public enum FirstRunFlow {
    public static func pendingSteps(
        permissions: PermissionStatus
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
        return steps.isEmpty ? [.ready] : steps
    }
}
