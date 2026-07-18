import AppKit
import Sparkle
import SlovoCore

/// Conforms Sparkle's updater to the pure activation seam. The property name
/// already matches, so enabling/disabling the scheduler flows through
/// `UpdaterActivation` and nothing assigns the switch directly. The conformance is
/// main-actor-isolated because `SPUUpdater.automaticallyChecksForUpdates` must be
/// touched on the main thread, which is where activation is always applied.
extension SPUUpdater: @MainActor UpdaterSwitch {}

/// Owns Slovo's silent Sparkle pipeline: one directly-constructed `SPUUpdater`, its
/// updater/user-driver delegates, and the current `UpdateIndication` folded from
/// Sparkle's callbacks. The silent path never touches the stock user driver, so no
/// Sparkle window can appear; the only self-relaunch is the user's Restart click.
///
/// Sparkle's delegate protocols are `@MainActor` (NS_SWIFT_UI_ACTOR), so the
/// callbacks land on the main actor and need no isolation hop.
@MainActor
final class UpdaterCoordinator: NSObject {
    /// The Sparkle updater, exposed as the pure `UpdaterSwitch` so the settings
    /// toggle and startup both drive it through `UpdaterActivation.apply`. Built
    /// lazily so it can wire `self` as both delegates without an unsafe unwrap.
    lazy var updater: SPUUpdater = {
        let driver = SPUStandardUserDriver(hostBundle: .main, delegate: self)
        return SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
    }()

    /// The current indication, folded from delegate events via `applying(_:)`.
    private(set) var currentIndication: UpdateIndication = .hidden

    /// Sparkle's stored install-on-quit handler. The Restart click is its only
    /// invoker, keeping the never-self-restart guarantee to a single call site.
    private var immediateInstallationBlock: (() -> Void)?

    /// Set only around a user-initiated install, so an abort during it is told apart
    /// from a background download failure: the former keeps the ready row and flashes
    /// the red glyph, the latter resets to hidden.
    private var isRestartInFlight = false

    private let onIndicationChange: (UpdateIndication) -> Void
    private let onInstallFailedAfterRestart: () -> Void

    init(
        onIndicationChange: @escaping (UpdateIndication) -> Void,
        onInstallFailedAfterRestart: @escaping () -> Void
    ) {
        self.onIndicationChange = onIndicationChange
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
        do {
            try updater.start()
        } catch {
            // A failed start surfaces nowhere (menu-bar-only rule); the next launch retries.
        }
    }

    /// Installs the already-downloaded update and relaunches — the one relaunch the
    /// never-self-restart gate allows, reached only from the user's Restart click.
    func installDownloadedUpdateAndRelaunch() {
        guard let immediateInstallationBlock else { return }
        isRestartInFlight = true
        immediateInstallationBlock()
    }

    private func reduce(_ event: UpdaterEvent) {
        currentIndication = currentIndication.applying(event)
        onIndicationChange(currentIndication)
    }

    private func handleAbort() {
        let wasRestartInFlight = isRestartInFlight
        isRestartInFlight = false
        reduce(.aborted)
        if wasRestartInFlight {
            // The user asked to restart and the immediate install failed: reduce
            // leaves the ready row intact (never regress a downloaded update); flash
            // the red glyph so the explicit action's failure is visible.
            onInstallFailedAfterRestart()
        }
    }
}

extension UpdaterCoordinator: SPUUpdaterDelegate {
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
        handleAbort()
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        handleAbort()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        handleAbort()
    }

    /// Never prompt for permission to check: the toggle is the single authority, and
    /// the silent pipeline has no permission UI.
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        false
    }
}

extension UpdaterCoordinator: SPUStandardUserDriverDelegate {
    /// Opt into gentle reminders so a downloaded-but-uninstalled update never
    /// escalates to a modal; our own menu-bar "Update ready" line is the reminder.
    /// `nonisolated` because this protocol (unlike `SPUUpdaterDelegate`) is not
    /// main-actor-annotated and the answer is a constant.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    /// Return false: the delegate owns showing scheduled updates, and by
    /// deliberately not implementing `standardUserDriverWillHandleShowingUpdate`,
    /// nothing is shown — the menu-bar "Update ready" line is the only reminder.
    /// Returning true would let the stock Sparkle alert appear on the fallback
    /// path (a translocated or non-writable /Applications copy).
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }
}
