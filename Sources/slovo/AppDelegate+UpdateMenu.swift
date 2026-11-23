import AppKit
import SlovoCore

extension AppDelegate {
    /// Builds and retains the Sparkle coordinator, applies the stored preference,
    /// and starts scheduled checks. The coordinator MUST be retained here: Sparkle
    /// holds its updater and user-driver delegates weakly, so without this strong
    /// reference the whole pipeline would deallocate immediately.
    func startUpdater() {
        let coordinator = UpdaterCoordinator(
            store: store,
            onUpdaterEvent: { [weak self] in self?.paintRestingGlyph() },
            onInstallFailedAfterRestart: { [weak self] in self?.flashUserActionFailure() }
        )
        updaterCoordinator = coordinator
        coordinator.start(automaticUpdatesEnabled: store.state.config.automaticallyInstallsUpdates)
    }

    /// The user-initiated Restart: installs the downloaded update and relaunches.
    /// This is the single relaunch invocation the never-self-restart gate allows.
    @objc
    func restartToInstallUpdate() {
        updaterCoordinator?.installDownloadedUpdateAndRelaunch()
    }

    /// The manual "Check for Updates…" action from the idle update row → the
    /// coordinator's silent background check (never the alert-showing user-driver check).
    @objc
    func checkForUpdatesManually() {
        updaterCoordinator?.checkForUpdates()
    }

    /// Writes the indication's row to the ONE persistent update row in place — never a
    /// rebuild, so the highlight callbacks survive a transition that happens while the
    /// dropdown is tracking. The row value (`UpdateIndication.row`) holds the texts and
    /// styles; this maps its action to the selector it triggers.
    func renderUpdateIndication(_ indication: UpdateIndication) {
        guard let item = updateMenuItem else { return }
        let row = indication.row
        switch row.action {
        case .noAction:
            item.action = nil
        case .checkNow:
            item.target = self
            item.action = #selector(checkForUpdatesManually)
        case .restart:
            item.target = self
            item.action = #selector(restartToInstallUpdate)
        }
        item.apply(row, highlighted: false)
    }

    /// Re-reads three system facts into state in one update: the live macOS fn
    /// assignment, the default output device's mute availability and the input
    /// devices. Their row listeners update the fn notice, the mute item and the
    /// Microphone submenu. Then it re-renders the update row from state, which undoes
    /// a highlight swap that left "Restart" on the row. The reads here keep the
    /// dropdown right even when a CoreAudio listener failed to register or was lost
    /// to an audio service reset. Called from `menuNeedsUpdate`, the callback Apple
    /// documents for changing menu items; `menuWillOpen` must not modify them.
    func resyncMenuFacts() {
        store.update {
            $0.isFnKeySystemAssigned = fnKeyAssignmentReader.isFnKeySystemAssigned
            $0.outputMuteAvailability = CoreAudioOutputMute().outputMuteAvailability()
            $0.inputDevices = CoreAudioInputDevices().inputDevices()
        }
        renderUpdateIndication(store.state.updateIndication)
    }

    /// The hybrid row: a grey status-line "Update ready — v…" when unhighlighted,
    /// swapping to a plain white "Restart" under highlight (like every actionable
    /// row). Only in the ready state; the accessibility label stays put across the swap.
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard let updateItem = updateMenuItem,
              case .ready = store.state.updateIndication
        else { return }
        updateItem.apply(store.state.updateIndication.row, highlighted: item === updateItem)
    }
}
