import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics

/// Real `PasteKeystroke` that synthesizes ⌘V via `CGEvent` (ref
/// `text-injection.md`).
///
/// Posting synthetic events requires the Accessibility grant, so this preflights
/// `AXIsProcessTrusted()` and surfaces `.accessibilityDenied` rather than letting
/// the OS silently drop the events (GAP-B). Event-creation failure maps to
/// `.pasteFailed`. It POSTS events (no `CGEventTap` callback), so the
/// closure-isolation crash that affects taps does not apply here.
///
/// Build-only / L4: compiles in CI, behavior validated by the Epic-07 manual
/// runbook. Stateless, so `Sendable` is safe.
public struct CGEventPasteKeystroke: PasteKeystroke, Sendable {
    public init() {}

    public func paste() throws {
        // Preflight: without the Accessibility grant, posted events are dropped
        // without error — refuse loudly instead.
        guard AXIsProcessTrusted() else {
            throw InjectionError.accessibilityDenied
        }

        let virtualV = CGKeyCode(kVK_ANSI_V)  // 0x09
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualV, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualV, keyDown: false)
        else {
            throw InjectionError.pasteFailed
        }

        // Both edges carry ⌘ so the receiving app sees a Command-V chord.
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}
