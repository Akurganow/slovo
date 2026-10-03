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
            onUpdaterEvent: { [weak self] in self?.repaintIdleGlyphForUpdateState() },
            onInstallFailedAfterRestart: { [weak self] in self?.flashUserActionFailure() }
        )
        updaterCoordinator = coordinator
        coordinator.start(automaticUpdatesEnabled: store.state.config.automaticallyInstallsUpdates)
    }

    /// The update-ready Nash rides the IDLE glyph slot, so every Sparkle callback
    /// repaints it — but never over a live dictation glyph, a brief failure flash, or
    /// the model-loading pulse; those paths re-derive the idle glyph through
    /// paintIdleGlyph when they settle. Onboarding never opens the model gate, so the
    /// onboarding menu mode stands in for model readiness there.
    func repaintIdleGlyphForUpdateState() {
        guard !isPipelineActive, !isShowingBriefStatus,
              isModelReady || store.state.menuMode.isOnboarding else { return }
        paintIdleGlyph(on: statusItem?.button)
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

    /// Mutates the ONE persistent update row in place from the indication — title
    /// and visibility only, never a rebuild, so the highlight callbacks survive a
    /// transition that happens while the dropdown is tracking.
    func renderUpdateIndication(_ indication: UpdateIndication) {
        guard let item = updateMenuItem else { return }
        switch indication {
        case .idle:
            // Always visible and actionable: an idle row offers a manual check.
            // Plain actionable style (not the grey status attributedTitle) — this is an
            // action the user takes, so it reads like every other actionable row.
            item.isHidden = false
            item.isEnabled = true
            item.target = self
            item.action = #selector(checkForUpdatesManually)
            item.title = "Check for Updates…"
            item.attributedTitle = nil
            // A ready-state label must not outlive the state: VoiceOver would keep
            // announcing "activate to restart" on a row that no longer restarts.
            item.setAccessibilityLabel(nil)
        case .checking:
            // Transient feedback while any check (scheduled or manual) is in flight;
            // grey status style, not actionable until the check finishes.
            item.isHidden = false
            item.isEnabled = false
            item.action = nil
            item.title = "Checking…"
            item.attributedTitle = Self.updateStatusTitle("Checking…")
            item.setAccessibilityLabel(nil)
        case .downloading(let version):
            item.isHidden = false
            item.isEnabled = false
            item.action = nil
            item.title = "Downloading v\(version)"
            item.attributedTitle = Self.updateStatusTitle("Downloading v\(version)")
            item.setAccessibilityLabel(nil)
        case .ready(let version):
            item.isHidden = false
            item.isEnabled = true
            item.target = self
            item.action = #selector(restartToInstallUpdate)
            item.title = "Update ready — v\(version)"
            item.attributedTitle = Self.updateStatusTitle("Update ready — v\(version)")
            // Stable action label independent of the highlight-driven title swap, so
            // VoiceOver and keyboard users get the action without the visual hover.
            item.setAccessibilityLabel("Update ready, version \(version), activate to restart")
        }
    }

    /// Re-reads two system facts into state in one update: the live macOS fn
    /// assignment and the default output device's mute availability. Their row
    /// listeners update the fn notice and the mute item. Then it re-renders the
    /// update row from state, which undoes a highlight swap that left "Restart" on
    /// the row. The read here keeps the dropdown right even when the CoreAudio
    /// listener failed to register or was lost to an audio service reset.
    func menuWillOpen(_ menu: NSMenu) {
        store.update {
            $0.isFnKeySystemAssigned = fnKeyAssignmentReader.isFnKeySystemAssigned
            $0.outputMuteAvailability = CoreAudioOutputMute().outputMuteAvailability()
        }
        renderUpdateIndication(store.state.updateIndication)
    }

    /// The hybrid row: a grey status-line "Update ready — v…" when unhighlighted,
    /// swapping to a plain white "Restart" under highlight (like every actionable
    /// row). Only in the ready state; the accessibility label stays put across the swap.
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard let updateItem = updateMenuItem,
              case .ready(let version) = store.state.updateIndication
        else { return }
        if item === updateItem {
            updateItem.attributedTitle = nil
            updateItem.title = "Restart"
        } else {
            updateItem.title = "Update ready — v\(version)"
            updateItem.attributedTitle = Self.updateStatusTitle("Update ready — v\(version)")
        }
    }

    /// A status-line-styled attributed title (secondaryLabelColor) so the update row
    /// reads like the disabled header lines until it is highlighted.
    private static func updateStatusTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.foregroundColor: NSColor.secondaryLabelColor])
    }
}
