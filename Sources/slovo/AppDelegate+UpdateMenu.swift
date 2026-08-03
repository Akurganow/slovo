import AppKit
import SlovoCore

extension AppDelegate {
    /// Builds and retains the Sparkle coordinator, applies the stored preference,
    /// and starts scheduled checks. The coordinator MUST be retained here: Sparkle
    /// holds its updater and user-driver delegates weakly, so without this strong
    /// reference the whole pipeline would deallocate immediately.
    func startUpdater() {
        let coordinator = UpdaterCoordinator(
            onIndicationChange: { [weak self] indication in
                self?.renderUpdateIndication(indication)
                self?.repaintIdleGlyphForUpdateState()
            },
            onInstallFailedAfterRestart: { [weak self] in self?.flashUpdateInstallFailure() }
        )
        updaterCoordinator = coordinator
        coordinator.start(automaticUpdatesEnabled: ConfigStore.load(from: defaults).automaticallyInstallsUpdates)
    }

    /// The update-ready Nash rides the IDLE glyph slot, so a ready/not-ready
    /// transition repaints it — but never over a live dictation glyph, a brief
    /// failure flash, or the model-loading pulse; those paths re-derive the idle
    /// glyph through paintIdleGlyph when they settle.
    func repaintIdleGlyphForUpdateState() {
        guard !isPipelineActive, !isShowingBriefStatus, isModelReady else { return }
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
            // Always visible and actionable now: an idle row offers a manual check.
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

    /// Re-syncs the two rows that track state living outside the menu — the
    /// fn-conflict notice and the update row — so a change that happened while the
    /// dropdown was closed lands no later than the next open.
    func menuWillOpen(_ menu: NSMenu) {
        // The user fixes the macOS fn assignment mid-session and expects the very
        // next open to reflect it, so the notice is a projection of the LIVE
        // setting; the build-time verdict only seeds it. Ahead of the update sync
        // below, which returns early when no coordinator exists.
        fnConflictMenuItem?.isHidden = !fnKeyAssignmentReader.isFnKeySystemAssigned
        guard let indication = updaterCoordinator?.currentIndication else { return }
        renderUpdateIndication(indication)
    }

    /// The hybrid row: a grey status-line "Update ready — v…" when unhighlighted,
    /// swapping to a plain white "Restart" under highlight (like every actionable
    /// row). Only in the ready state; the accessibility label stays put across the swap.
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard let updateItem = updateMenuItem,
              case .ready(let version)? = updaterCoordinator?.currentIndication
        else { return }
        if item === updateItem {
            updateItem.attributedTitle = nil
            updateItem.title = "Restart"
        } else {
            updateItem.title = "Update ready — v\(version)"
            updateItem.attributedTitle = Self.updateStatusTitle("Update ready — v\(version)")
        }
    }

    /// Briefly flashes the red failure glyph (the empty-dictation pattern) when a
    /// user-initiated install fails, then restores idle — the only update failure the
    /// user ever sees, because they explicitly acted; background failures stay silent.
    func flashUpdateInstallFailure() {
        guard let button = statusItem?.button else { return }
        button.title = ""
        button.contentTintColor = nil
        button.image = MenuBarGlyph.image(for: MenuBarGlyph.failureGlyph, tint: .error)
            ?? NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "Slovo")
        // Tracked reset, mirroring briefStatusResetTask: cancel any pending reset before
        // scheduling anew, and skip the reset if superseded or if a dictation started
        // within the window (its recording glyph must not be stomped back to idle).
        updateFailureResetTask?.cancel()
        updateFailureResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, self?.isPipelineActive == false else { return }
            self?.paintIdleGlyph(on: self?.statusItem?.button)
        }
    }

    /// A status-line-styled attributed title (secondaryLabelColor) so the update row
    /// reads like the disabled header lines until it is highlighted.
    private static func updateStatusTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.foregroundColor: NSColor.secondaryLabelColor])
    }
}
