import AppKit
import SlovoCore

extension AppDelegate {
    /// Builds and retains the Sparkle coordinator, applies the stored preference,
    /// and starts scheduled checks. The coordinator MUST be retained here: Sparkle
    /// holds its updater and user-driver delegates weakly, so without this strong
    /// reference the whole pipeline would deallocate immediately.
    func startUpdater() {
        let coordinator = UpdaterCoordinator(
            onIndicationChange: { [weak self] indication in self?.renderUpdateIndication(indication) },
            onInstallFailedAfterRestart: { [weak self] in self?.flashUpdateInstallFailure() }
        )
        updaterCoordinator = coordinator
        coordinator.start(automaticUpdatesEnabled: ConfigStore.load(from: defaults).automaticallyInstallsUpdates)
    }

    /// The user-initiated Restart: installs the downloaded update and relaunches.
    /// This is the single relaunch invocation the never-self-restart gate allows.
    @objc
    func restartToInstallUpdate() {
        updaterCoordinator?.installDownloadedUpdateAndRelaunch()
    }

    /// Mutates the ONE persistent update row in place from the indication — title
    /// and visibility only, never a rebuild, so the highlight callbacks survive a
    /// transition that happens while the dropdown is tracking.
    func renderUpdateIndication(_ indication: UpdateIndication) {
        guard let item = updateMenuItem else { return }
        switch indication {
        case .hidden:
            item.isHidden = true
            item.isEnabled = false
            item.action = nil
            // A ready-state label must not outlive the state: VoiceOver would keep
            // announcing "activate to restart" on a row that no longer restarts.
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

    /// Re-syncs the update row from the coordinator on every open, so a transition
    /// that happened while the dropdown was closed lands no later than the next open.
    func menuWillOpen(_ menu: NSMenu) {
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
        button.image = MenuBarGlyph.image(for: "\u{2C11}", tint: .error)
            ?? NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "Slovo")
        // Tracked reset, mirroring sadToFailResetTask: cancel any pending reset before
        // scheduling anew, and skip the reset if superseded or if a dictation started
        // within the window (its recording glyph must not be stomped back to idle).
        updateFailureResetTask?.cancel()
        updateFailureResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, self?.isPipelineActive == false else { return }
            self?.setStatusGlyph(.idle, on: self?.statusItem?.button)
        }
    }

    /// A status-line-styled attributed title (secondaryLabelColor) so the update row
    /// reads like the disabled header lines until it is highlighted.
    private static func updateStatusTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.foregroundColor: NSColor.secondaryLabelColor])
    }
}
