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

    /// Writes the row to the ONE persistent update row in place — never a
    /// rebuild, so the highlight callbacks survive a transition that happens while the
    /// dropdown is tracking. The row value (`AppState.updateRow`) holds the texts and
    /// styles; this maps its action to the selector it triggers.
    func renderUpdateRow(_ row: UpdateRow) {
        guard let item = updateMenuItem else { return }
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

    /// The hybrid row: a grey status line ("Update Ready — v…", "Update Check Failed")
    /// when unhighlighted, swapping to a plain white action title under highlight (like
    /// every actionable row). Only for a row that has a highlighted title; the
    /// accessibility label stays put across the swap.
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        let row = store.state.updateRow
        guard let updateItem = updateMenuItem, row.highlightedTitle != nil else { return }
        updateItem.apply(row, highlighted: item === updateItem)
    }
}
