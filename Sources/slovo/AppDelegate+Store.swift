import Foundation
import SlovoCore

extension AppDelegate {
    /// Wires every effect of the store, once per launch. Called after `statusItem`
    /// exists and before `startPipeline()`: earlier, the menu subscriber's first
    /// build would write into a nil status item; later, it would replace an
    /// onboarding menu that `startPipeline` installed.
    func startStoreEffects() {
        let keyProvider = openRouterKeyProvider
        AppStoreEffects.wire(store, to: AppStoreEffectTargets(
            defaults: defaults,
            orchestrator: { [weak self] in self?.composition?.orchestrator },
            reconfigureHotkeys: { [weak self] in self?.composition?.hotkeyMonitor.reconfigure(configuration: $0) },
            cueController: { [weak self] in self?.composition?.cueController },
            updaterSwitch: { [weak self] in self?.updaterCoordinator?.updater },
            // Built per fetch over the app's one key provider: no second Keychain
            // read path, no stored fetcher.
            fetchScopeIds: {
                try await OpenRouterModelScopeFetcher(
                    session: URLSession(configuration: .ephemeral),
                    keyProvider: keyProvider
                ).fetchScopeIds()
            }
        ))
        store.subscribe(\.dictationMenuInput) { [weak self] input in
            self?.installStatusMenu(input)
        }
        store.listen(\.isFnKeySystemAssigned) { [weak self] isAssigned in
            self?.fnConflictMenuItem?.isHidden = !isAssigned
        }
        store.listen(\.updateIndication) { [weak self] indication in
            self?.renderUpdateIndication(indication)
        }
    }
}
