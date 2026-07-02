import AppKit
import QuartzCore
import SlovoCore

extension AppDelegate {
    func setStatusGlyph(_ state: DictationState, on button: NSStatusBarButton?) {
        guard let button else { return }
        button.title = ""
        button.contentTintColor = nil
        button.image = Self.menuBarGlyphImage(MenuBarGlyph.forState(state))
            ?? NSImage(systemSymbolName: "mic", accessibilityDescription: "Slovo")
    }

    func setStatusGlyph(status: StatusMessage, on button: NSStatusBarButton?) {
        guard let button, let glyph = MenuBarGlyph.forStatus(status) else { return }
        button.title = ""
        button.contentTintColor = MenuBarGlyph.tint(forStatus: status) == .error ? .systemRed : nil
        button.image = Self.menuBarGlyphImage(glyph)
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

    static func menuBarGlyphImage(_ glyph: Character) -> NSImage? {
        guard let font = NSFont(name: "NotoSansGlagolitic-Regular", size: 16) else {
            return nil
        }
        let text = NSAttributedString(
            string: String(glyph),
            attributes: [
                .font: font,
                .foregroundColor: NSColor.black,
            ]
        )
        let textSize = text.size()
        let image = NSImage(size: NSSize(width: ceil(textSize.width), height: ceil(textSize.height)))
        image.lockFocus()
        text.draw(at: .zero)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
