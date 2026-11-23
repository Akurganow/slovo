import Foundation
import os
import Sparkle
import SlovoCore

/// Conforms Sparkle's updater to the pure activation seam. The property name
/// already matches, so enabling/disabling the scheduler flows through
/// `UpdaterActivation` and nothing assigns the switch directly. The conformance is
/// main-actor-isolated because `SPUUpdater.automaticallyChecksForUpdates` must be
/// touched on the main thread, which is where activation is always applied.
extension SPUUpdater: @MainActor UpdaterSwitch {}

/// Owns Slovo's silent Sparkle pipeline: one directly-constructed `SPUUpdater` and
/// its updater/user-driver delegates. It folds Sparkle's callbacks into
/// `AppState.updateIndication` and `AppState.canCheckForUpdates`. The silent path never touches the stock user
/// driver, so no Sparkle window can appear; the only self-relaunch is the user's
/// Restart click.
///
/// Sparkle's delegate protocols are `@MainActor` (NS_SWIFT_UI_ACTOR), so the
/// callbacks land on the main actor and need no isolation hop.
@MainActor
final class UpdaterCoordinator: NSObject {
    private static let log = Logger(subsystem: "com.slovo.app", category: "update")

    /// The Sparkle updater, exposed as the pure `UpdaterSwitch` so the settings
    /// toggle and startup both drive it through `UpdaterActivation.apply`. Built
    /// lazily so it can wire `self` as both delegates without an unsafe unwrap.
    lazy var updater: SPUUpdater = {
        let driver = SPUStandardUserDriver(hostBundle: .main, delegate: self)
        return SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
    }()

    /// Sparkle's stored install-on-quit handler. The Restart click is its only
    /// invoker, keeping the never-self-restart guarantee to a single call site.
    private var immediateInstallationBlock: (() -> Void)?

    /// Set only around a user-initiated install, so an abort during it is told apart
    /// from a background download failure: the former keeps the ready row and flashes
    /// the red glyph, the latter resets to hidden.
    private var isRestartInFlight = false

    /// Keeps the `canCheckForUpdates` observation alive; dropping it ends the observation.
    private var canCheckObservation: NSKeyValueObservation?

    private let store: AppStore
    private let onUpdaterEvent: () -> Void
    private let onInstallFailedAfterRestart: () -> Void

    init(
        store: AppStore,
        onUpdaterEvent: @escaping () -> Void,
        onInstallFailedAfterRestart: @escaping () -> Void
    ) {
        self.store = store
        self.onUpdaterEvent = onUpdaterEvent
        self.onInstallFailedAfterRestart = onInstallFailedAfterRestart
        super.init()
    }

    /// Applies the stored preference, THEN starts scheduled checks — activation
    /// first, so an off user never gets even the first scheduled check.
    func start(automaticUpdatesEnabled: Bool) {
        UpdaterActivation.apply(automaticUpdatesEnabled: automaticUpdatesEnabled, to: updater)
        startUpdater()
    }

    private func startUpdater() {
        observeCanCheckForUpdates()
        do {
            try updater.start()
        } catch {
            // The log line is the only surface (menu-bar-only rule); the next launch retries.
            Self.log.error("updater did not start, code \((error as NSError).code)")
        }
    }

    /// Writes the updater's `canCheckForUpdates` into the store, now and on every change,
    /// so the check row acts only while Sparkle says a check can start.
    /// `SPUUpdater.h`, Sparkle 2.10.1: "This property is suitable to use for menu item
    /// validation for seeing if `-checkForUpdates` can be invoked. This property is also
    /// KVO-compliant." The change handler is not main-actor-isolated, so it hops to the
    /// main actor and reads the live value there, which keeps the final write the latest.
    private func observeCanCheckForUpdates() {
        canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.syncCanCheckForUpdates()
            }
        }
    }

    private func syncCanCheckForUpdates() {
        let canCheck = updater.canCheckForUpdates
        store.update { $0.canCheckForUpdates = canCheck }
    }

    /// Installs the already-downloaded update and relaunches — the one relaunch the
    /// never-self-restart gate allows, reached only from the user's Restart click.
    func installDownloadedUpdateAndRelaunch() {
        guard let immediateInstallationBlock else { return }
        isRestartInFlight = true
        immediateInstallationBlock()
    }

    /// The manual "Check for Updates…" action. Uses `checkForUpdatesInBackground()`,
    /// NOT `checkForUpdates()`: the latter drives the standard user driver's progress
    /// window and "you're up to date" alert, which the silent, menu-bar-only pipeline
    /// must never show. The background call routes any found update through the same
    /// gentle-reminder path as a scheduled check, so it surfaces only in our menu row.
    /// Guarded on `canCheckForUpdates` so we never show "Checking…" for a check that
    /// cannot start; the optimistic `.checkStarted` gives immediate feedback, and the
    /// `mayPerformUpdateCheck` gate reaches the same state for scheduled checks too.
    /// (Sparkle warns direct calls can interfere with its scheduler — acceptable for a
    /// user-initiated check; the guaranteed `didFinishUpdateCycle` terminal un-sticks
    /// `checking` regardless.)
    func checkForUpdates() {
        guard updater.canCheckForUpdates else { return }
        reduce(.checkStarted)
        updater.checkForUpdatesInBackground()
    }

    /// Folds the event into the store, then reports it. The report runs on every
    /// event, changed or not: the idle glyph repaints on each Sparkle callback
    /// (docs/architecture.md, "App State").
    private func reduce(_ event: UpdaterEvent) {
        store.update { $0.updateIndication = $0.updateIndication.applying(event) }
        onUpdaterEvent()
    }

    /// The one place that ends a Restart: `event` is `.failed` when the check or the
    /// download failed and `.aborted` when it stopped without a failure.
    private func handleAbort(_ event: UpdaterEvent) {
        let wasRestartInFlight = isRestartInFlight
        isRestartInFlight = false
        reduce(event)
        if wasRestartInFlight {
            // The user asked to restart and the immediate install failed: reduce
            // leaves the ready row intact (never regress a downloaded update); flash
            // the red glyph so the explicit action's failure is visible.
            onInstallFailedAfterRestart()
        }
    }
}

extension UpdaterCoordinator: SPUUpdaterDelegate {
    /// The permission gate Sparkle calls before EVERY check (scheduled OR
    /// user-initiated). We always allow — the toggle is the single authority, so this
    /// never throws — and use this one hook, which fires for every check start, to show
    /// "Checking…" for scheduled checks too, not only the manual button.
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        reduce(.checkStarted)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        reduce(.found)
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        reduce(.downloadStarted(version: item.displayVersionString))
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock: @escaping () -> Void
    ) -> Bool {
        self.immediateInstallationBlock = immediateInstallationBlock
        reduce(.downloaded(version: item.displayVersionString))
        return true
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        handleAbort(.failed)
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        handleAbort(.aborted)
    }

    /// Sparkle reports a check that found no update here too, as `SUNoUpdateError`
    /// (`SPUUpdaterDelegate.h`, Sparkle 2.10.1). That one is no failure and is not
    /// logged; every other error is a failed check.
    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let error = error as NSError
        guard error.domain != SUSparkleErrorDomain || error.code != Int(SUError.noUpdateError.rawValue) else {
            handleAbort(.aborted)
            return
        }
        Self.log.error("update check aborted, code \(error.code)")
        handleAbort(.failed)
    }

    /// A check finished finding no newer version: return the row from "Checking…" to
    /// the idle "Check for Updates…" line.
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        reduce(.notFound)
    }

    /// Sparkle's GUARANTEED terminal, fired at the end of every check cycle regardless
    /// of outcome — the backstop that keeps "Checking…" from sticking even when a check
    /// found an update it did not download, or ended in a way no other callback reports.
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        reduce(.checkFinished)
    }

    /// Never prompt for permission to check: the toggle is the single authority, and
    /// the silent pipeline has no permission UI.
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        false
    }
}

extension UpdaterCoordinator: SPUStandardUserDriverDelegate {
    /// Opt into gentle reminders so a downloaded-but-uninstalled update never
    /// escalates to a modal; our own menu-bar "Update Ready" line is the reminder.
    /// `nonisolated` because this protocol (unlike `SPUUpdaterDelegate`) is not
    /// main-actor-annotated and the answer is a constant.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    /// Return false: the delegate owns showing scheduled updates, and by
    /// deliberately not implementing `standardUserDriverWillHandleShowingUpdate`,
    /// nothing is shown — the menu-bar "Update Ready" line is the only reminder.
    /// Returning true would let the stock Sparkle alert appear on the fallback
    /// path (a translocated or non-writable /Applications copy).
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }
}
