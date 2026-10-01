import SlovoCore

extension AppDelegate {
    /// The K8 observer handed to `AppComposition.makeLive` — the same actor hop
    /// as `statusReporter`, one line at the call site (lint budget). A cleanup
    /// failure becomes a scope event in the store.
    func scopeFailureObserver() -> (@Sendable (CleanupError) -> Void) {
        { [weak self] error in
            Task { @MainActor [weak self] in
                self?.store.update { $0.applyScope(.cleanupFailed(error)) }
            }
        }
    }
}
