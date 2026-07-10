import CoreGraphics

/// Real `CGEventTap` implementation of `HotkeyMonitor`. Observes `flagsChanged`
/// (trigger edges) and `keyDown` (combo interrupts), reduces each event to a
/// `HotkeyInputEvent`, and lets the tap-free `HotkeyDecisionCore` decide the
/// action — emitting `.down`/`.up`/`.cancel` and suppressing or passing the event
/// through. If the tap is disabled by timeout or user input it is re-enabled, and
/// a held trigger is released via a synthesized `.up`. A `tapIsEnabled` poll lets
/// a supervisor recreate a dead tap.
///
/// Exercised on real hardware via the manual runbook, not in CI; its decision
/// logic is unit-tested through `HotkeyDecisionCore`.
public final class CGEventTapHotkeyMonitor: HotkeyMonitor {
    public struct HotkeyTapError: Error {
        public let reason: String
    }

    public var onTrigger: ((HotkeyPhase) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var decisionCore: HotkeyDecisionCore

    public init(trigger: HotkeyTrigger) {
        self.decisionCore = HotkeyDecisionCore(trigger: trigger)
    }

    /// The tap holds `self` UNRETAINED via `refcon`; tear it down before the
    /// monitor dies so the callback can never dereference a dangling pointer.
    deinit {
        stop()
    }

    /// Whether the tap is currently installed and enabled.
    public var tapIsEnabled: Bool {
        guard let eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    /// Applies a live trigger change in place. The event mask is
    /// trigger-independent, so only the decision core is swapped (held state
    /// reset) — no tap teardown, no failure window, no pipeline rebuild.
    public func reconfigure(trigger: HotkeyTrigger) {
        decisionCore.reconfigure(to: trigger)
    }

    public func start() throws {
        // keyDown joins flagsChanged so the tap can observe an interrupting key
        // press and cancel a right-modifier hold.
        let eventMask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        )
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyEventTapCallback,
            userInfo: userInfo
        ) else {
            throw HotkeyTapError(reason: "CGEvent.tapCreate returned nil (Input Monitoring not granted?)")
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
    }

    public func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Tap callback

    /// Dispatched to from the top-level C callback via the `refcon` pointer.
    fileprivate func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let inputEvent: HotkeyInputEvent
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            inputEvent = .tapDisabled
        case .flagsChanged:
            inputEvent = .flagsChanged(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                flags: Self.modifierFlags(from: event.flags)
            )
        case .keyDown:
            // Privacy invariant: a non-trigger key press contributes ONLY the fact
            // that a key went down. Its key code and typed character are never read
            // here, so keystroke content cannot be logged or retained.
            inputEvent = .keyDown
        default:
            return Unmanaged.passUnretained(event)
        }

        switch decisionCore.handle(inputEvent) {
        case .start(let suppress):
            onTrigger?(.down)
            return suppress ? nil : Unmanaged.passUnretained(event)
        case .stop(let suppress):
            onTrigger?(.up)
            return suppress ? nil : Unmanaged.passUnretained(event)
        case .interruptCancel:
            onTrigger?(.cancel)
            // The real combo (e.g. Right ⌘ + C) must proceed untouched.
            return Unmanaged.passUnretained(event)
        case .resync(let synthesizeUp):
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            if synthesizeUp {
                onTrigger?(.up)
            }
            return Unmanaged.passUnretained(event)
        case .passThrough:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Reduces the live `CGEventFlags` to just the five bits the decision reads.
    private static func modifierFlags(from flags: CGEventFlags) -> HotkeyModifierFlags {
        var result: HotkeyModifierFlags = []
        if flags.contains(.maskSecondaryFn) { result.insert(.secondaryFn) }
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        return result
    }
}

/// Top-level C callback for the event tap. A `CGEventTap` callback cannot capture
/// context, so it recovers the owning monitor from the `refcon` pointer and
/// dispatches into it. Kept top-level (not a closure literal at the `tapCreate`
/// call site) to avoid a Swift 6 region-isolation analysis crash on the closure.
private func hotkeyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<CGEventTapHotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
    return monitor.process(type: type, event: event)
}
