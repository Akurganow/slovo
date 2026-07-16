import AppKit
import QuartzCore
import SlovoCore

extension AppDelegate {
    func setStatusGlyph(_ state: DictationState, on button: NSStatusBarButton?) {
        guard let button else { return }
        button.title = ""
        button.contentTintColor = nil
        button.image = MenuBarGlyph.image(for: MenuBarGlyph.forState(state), tint: .normal)
            ?? NSImage(systemSymbolName: "mic", accessibilityDescription: "Slovo")
    }

    func setStatusGlyph(status: StatusMessage, on button: NSStatusBarButton?) {
        guard let button, let glyph = MenuBarGlyph.forStatus(status) else { return }
        button.title = ""
        // Clear any prior tint; the glyph color now rides on the image itself
        // (see MenuBarGlyph.image(for:tint:)).
        button.contentTintColor = nil
        button.image = MenuBarGlyph.image(for: glyph, tint: MenuBarGlyph.tint(forStatus: status))
            ?? NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "Slovo")
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
