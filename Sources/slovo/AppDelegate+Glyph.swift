import AppKit
import QuartzCore
import SlovoCore

extension AppDelegate {
    /// The single funnel for the resting menu-bar glyph: idle is a projection of
    /// update state, so every "back to idle" path routes through here — a direct
    /// `setStatusGlyph(.idle)` call would silently drop the update-ready Nash Ⱀ
    /// while a downloaded update awaits Restart.
    func paintIdleGlyph(on button: NSStatusBarButton?) {
        guard let button else { return }
        let isUpdateReady: Bool
        if case .ready = store.state.updateIndication {
            isUpdateReady = true
        } else {
            isUpdateReady = false
        }
        paint(MenuBarGlyph.idleGlyph(isUpdateReady: isUpdateReady), tint: .normal, fallbackSymbol: "mic", on: button)
    }

    func setStatusGlyph(_ state: DictationState, on button: NSStatusBarButton?) {
        guard let button else { return }
        paint(MenuBarGlyph.forState(state), tint: .normal, fallbackSymbol: "mic", on: button)
    }

    /// Paints the recording glyph for the session's mode — the semantic family
    /// Ⱍ clean / Ⰳ raw / Ⱂ translate — so the mode (a translate hold that latches
    /// live mid-hold, or raw when cleanup is off) is visible in the menu bar while
    /// the key is still held.
    func setStatusGlyph(recording mode: RecordingGlyphMode, on button: NSStatusBarButton?) {
        guard let button else { return }
        paint(MenuBarGlyph.forRecording(mode: mode), tint: .normal, fallbackSymbol: "mic", on: button)
    }

    func setStatusGlyph(status: StatusMessage, on button: NSStatusBarButton?) {
        guard let button else { return }
        paint(
            MenuBarGlyph.forStatus(status),
            tint: MenuBarGlyph.tint(forStatus: status),
            fallbackSymbol: "exclamationmark.circle",
            on: button
        )
    }

    /// The one write of a glyph to the status button. The glyph color rides on the
    /// image itself (see `MenuBarGlyph.image(for:tint:)`), so a tint left on the
    /// button from an earlier paint is cleared. `fallbackSymbol` shows when the
    /// glyph image cannot be built.
    private func paint(_ glyph: Character, tint: MenuBarGlyphTint, fallbackSymbol: String, on button: NSStatusBarButton) {
        button.title = ""
        button.contentTintColor = nil
        button.image = MenuBarGlyph.image(for: glyph, tint: tint)
            ?? NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: "Slovo")
    }

    /// Briefly flashes the red failure glyph (the empty-dictation pattern) when an
    /// action the user explicitly took fails — a Restart install, a key save or a
    /// key removal — then restores idle. Background failures stay silent.
    func flashUserActionFailure() {
        guard let button = statusItem?.button else { return }
        paint(MenuBarGlyph.failureGlyph, tint: .error, fallbackSymbol: "exclamationmark.circle", on: button)
        // Tracked reset, mirroring briefStatusResetTask: cancel any pending reset before
        // scheduling anew, and skip the reset if superseded or if a dictation started
        // within the window (its recording glyph must not be stomped back to idle).
        userActionFailureResetTask?.cancel()
        userActionFailureResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, self?.isPipelineActive == false else { return }
            self?.paintIdleGlyph(on: self?.statusItem?.button)
        }
    }

    private static let modelLoadingPulseKey = "model-loading-pulse"

    /// Breathing pulse for the model-loading glyph. Timing follows the system
    /// attention-pulse feel: ease-in-out, ~1.5 s full cycle (0.75 s per leg),
    /// dimming to 30% — slower than the 1 Hz text caret, faster than the 3–5 s
    /// sleep-indicator breath, so it reads as "working", not "alarmed".
    func startModelLoadingPulse(on button: NSStatusBarButton?) {
        guard let button else { return }
        button.wantsLayer = true
        guard button.layer?.animation(forKey: Self.modelLoadingPulseKey) == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 0.75
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        button.layer?.add(pulse, forKey: Self.modelLoadingPulseKey)
    }

    func stopModelLoadingPulse(on button: NSStatusBarButton?) {
        button?.layer?.removeAnimation(forKey: Self.modelLoadingPulseKey)
        button?.layer?.opacity = 1
    }
}
