import Foundation
import SlovoCore

/// The scope funnel (spec rev 3 §4 K6/K11): executes the reducer's commands and
/// feeds completions back as events. The ONLY writer of `scopeState` and
/// `cleanupModelScopeModel`; it never writes config (K1) — guards pin both.
extension AppDelegate {
    func applyScopeEvent(_ event: CleanupScopeEvent) {
        let (newState, commands) = CleanupScopeReducer.reduce(scopeState, event)
        // Commit state BEFORE executing commands — load-bearing: a command may
        // re-enter this funnel (push → feedAvailabilityEdge), and termination
        // depends on the re-entrant read seeing the new value.
        self.scopeState = newState
        cleanupModelScopeModel.update(newState.scope)
        for command in commands {
            switch command {
            case .fetch(let generation):
                // Built per fetch: a value struct over the app's ONE key provider
                // (internal `let openRouterKeyProvider`, AppDelegate.swift:17) —
                // no second Keychain read path (§9.1), no stored property.
                let fetcher = OpenRouterModelScopeFetcher(
                    session: URLSession(configuration: .ephemeral),
                    keyProvider: openRouterKeyProvider
                )
                Task { [weak self] in
                    let ids = try? await fetcher.fetchScopeIds()
                    await MainActor.run { self?.applyScopeEvent(.fetchCompleted(generation: generation, ids: ids)) }
                }
            case .pushEffectiveConfig:
                pushEffectiveCleanupConfig()
            case .rebuildMenu:
                installStatusMenu()
            }
        }
    }

    /// The K8 observer handed to `AppComposition.makeLive` — the same actor hop
    /// as `statusReporter`, one line at the call site (lint budget).
    func scopeFailureObserver() -> (@Sendable (CleanupError) -> Void) {
        { [weak self] error in
            Task { @MainActor [weak self] in
                self?.applyScopeEvent(.cleanupFailed(error))
            }
        }
    }

    /// Feeds the availability EDGE only — a same-value feed is filtered here AND
    /// no-opped by the reducer, so pipeline restarts never reset a known scope.
    func feedAvailabilityEdge() {
        let isOn = currentCleanupAvailability().isOn
        guard isOn != scopeState.cleanupIsOn else { return }
        applyScopeEvent(.availabilityChanged(isOn: isOn))
    }

    /// The one K2 derivation both surfaces render (K3/K6): Settings picker and
    /// menu submenu call this — never CleanupModelCatalog.options directly.
    func currentModelSelection() -> CleanupModelSelection.Result {
        CleanupModelSelection.derive(
            preference: currentConfig().openRouterModel,
            catalog: CleanupModelCatalog.options,
            scope: scopeState.scope
        )
    }
}
