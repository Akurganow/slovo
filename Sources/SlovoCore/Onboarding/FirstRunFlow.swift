public enum OnboardingStep: Equatable, Sendable {
    case requestMicrophone
    case requestAccessibility
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
        return steps.isEmpty ? [.ready] : steps
    }
}
