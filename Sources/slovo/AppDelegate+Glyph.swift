import AppKit
import QuartzCore
import SlovoCore

extension AppDelegate {
    /// Paints the glyph the menu bar shows when no flash and no notice holds it: a
    /// live dictation's hold glyph, the loading glyph and its pulse, or idle. The
    /// decision is `RestingGlyph.derive`. Idle is reached only through here, since
    /// idle is a projection of update state: painting the idle glyph directly would
    /// silently drop the update-ready Nash Ⱀ while a downloaded update awaits
    /// Restart. Every Sparkle callback calls this, because the Nash rides the idle
    /// slot; the decision keeps that repaint off the dictation-failure flash and
    /// gives a live dictation its hold glyph. The user-action failure flash sets no
    /// latch, so a later Sparkle event repaints over it on purpose
    /// (`docs/architecture.md`, "App State").
    func paintRestingGlyph() {
        guard let button = statusItem?.button else { return }
        let resting = RestingGlyph.derive(
            isShowingBriefStatus: isShowingBriefStatus,
            liveDictation: liveDictation,
            gate: modelGate
        )
        // Only `.loading` keeps the pulse. Any other result ends it, so a dictation glyph
        // painted over the loading glyph does not keep pulsing.
        if resting != .loading { stopModelLoadingPulse(on: button) }
        switch resting {
        case .leave:
            break
        case .hold:
            paintHoldGlyph()
        case .loading:
            setStatusGlyph(status: .preparingSpeechModel, on: button)
            startModelLoadingPulse(on: button)
        case .idle:
            paintIdleGlyph(on: button)
        }
    }

    private func paintIdleGlyph(on button: NSStatusBarButton) {
        let isUpdateReady: Bool
        if case .ready = store.state.updateIndication {
            isUpdateReady = true
        } else {
            isUpdateReady = false
        }
        paint(MenuBarGlyph.idleGlyph(isUpdateReady: isUpdateReady), tint: .normal, fallbackSymbol: "mic", on: button)
    }

    /// Paints the live dictation's glyph for its phase: the recording family
    /// Ⱍ clean / Ⰳ raw / Ⱂ translate while the key is held, the processing glyph
    /// after key-up. The only read of the live cleanup setting for this glyph, so
    /// raw wins over a translate key that joined mid-hold.
    private func paintHoldGlyph() {
        guard let button = statusItem?.button, case .hold(let phase) = liveDictation else { return }
        let glyph = MenuBarGlyph.forHold(phase, isCleanupOn: store.state.cleanupAvailability.isOn)
        paint(glyph, tint: .normal, fallbackSymbol: "mic", on: button)
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
        button.setAccessibilityLabel("Slovo")
        button.image = MenuBarGlyph.image(for: glyph, tint: tint)
            ?? NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: "Slovo")
    }

    /// Briefly flashes the red failure glyph (the empty-dictation pattern) when an
    /// action the user explicitly took fails — a Restart install, a key save or removal,
    /// a vocabulary edit, or opening the notices file or a System Settings pane — then
    /// restores the resting glyph. Background failures stay silent.
    func flashUserActionFailure() {
        guard let button = statusItem?.button else { return }
        paint(MenuBarGlyph.failureGlyph, tint: .error, fallbackSymbol: "exclamationmark.circle", on: button)
        // Tracked reset, mirroring briefStatusResetTask: cancel any pending reset before
        // scheduling anew, and skip the reset if superseded. The repaint goes through
        // the resting decision, so a dictation that started within the window gets
        // its hold glyph back, not idle.
        userActionFailureResetTask?.cancel()
        userActionFailureResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.paintRestingGlyph()
        }
    }

    private static let modelLoadingPulseKey = "model-loading-pulse"

    /// Breathing pulse for the model-loading glyph. Timing follows the system
    /// attention-pulse feel: ease-in-out, ~1.5 s full cycle (0.75 s per leg),
    /// dimming to 30% — slower than the 1 Hz text caret, faster than the 3–5 s
    /// sleep-indicator breath, so it reads as "working", not "alarmed".
    private func startModelLoadingPulse(on button: NSStatusBarButton) {
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

    private func stopModelLoadingPulse(on button: NSStatusBarButton) {
        button.layer?.removeAnimation(forKey: Self.modelLoadingPulseKey)
        button.layer?.opacity = 1
    }
}
