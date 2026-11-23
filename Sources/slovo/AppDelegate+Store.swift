import Foundation
import SlovoCore

extension AppDelegate {
    /// Wires every effect of the store, once per launch. Called after `statusItem`
    /// exists: earlier, the build subscriber's first build would write into a nil
    /// status item. It runs before `startPipeline()`, whose menu-mode write the
    /// build subscriber then draws.
    func startStoreEffects() {
        let keyProvider = openRouterKeyProvider
        let scopeFetchConfiguration = URLSessionConfiguration.ephemeral
        // No URL cache: fetches under different keys must never share a cached response.
        scopeFetchConfiguration.urlCache = nil
        let scopeFetchSession = URLSession(configuration: scopeFetchConfiguration)
        AppStoreEffects.wire(store, to: AppStoreEffectTargets(
            defaults: defaults,
            reconfigureHotkeys: { [weak self] in self?.composition?.hotkeyMonitor.reconfigure(configuration: $0) },
            cueController: { [weak self] in self?.composition?.cueController },
            updaterSwitch: { [weak self] in self?.updaterCoordinator?.updater },
            updateInputDevice: { [weak self] in self?.composition?.recorder.updatePreferredInputDevice($0) },
            // One session for the app's lifetime; the fetcher is built per fetch over
            // the app's one key provider: no second Keychain read path, no stored
            // fetcher.
            fetchScopeIds: {
                try await OpenRouterModelScopeFetcher(
                    session: scopeFetchSession,
                    keyProvider: keyProvider
                ).fetchScopeIds()
            }
        ))
        // The build runs before the row listeners, so in one update that changes the
        // structure and a row, the listener rewrites the value the build just set.
        store.subscribe(\.menuStructure) { [weak self] structure in
            guard let self else { return }
            switch structure.mode {
            case .dictation:
                let state = store.state
                statusItem?.menu = makeMenu(
                    structure.input,
                    rows: DictationMenuRows(statusLine: state.statusLineText, isFnKeySystemAssigned: state.isFnKeySystemAssigned),
                    updateRow: state.updateRow,
                    muteAvailability: state.outputMuteAvailability,
                    inputDeviceChoice: state.inputDeviceChoice
                )
            case .onboarding(let steps):
                statusItem?.menu = makeOnboardingMenu(for: steps)
            case .hotkeyRecovery:
                statusItem?.menu = makeHotkeyRecoveryMenu()
            }
        }
        store.listen(\.statusLineText) { [weak self] text in
            self?.statusTextItem?.title = text
        }
        store.listen(\.isFnKeySystemAssigned) { [weak self] isAssigned in
            self?.fnConflictMenuItem?.isHidden = !isAssigned
        }
        store.listen(\.updateRow) { [weak self] row in
            self?.renderUpdateRow(row)
        }
        store.listen(\.outputMuteAvailability) { [weak self] availability in
            self?.renderMuteAvailability(availability)
        }
        store.listen(\.inputDeviceChoice) { [weak self] choice in
            self?.renderMicrophoneMenu(choice)
        }
    }
}
