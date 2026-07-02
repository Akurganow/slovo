import CoreGraphics

/// Real `CGEventTap` implementation of `HotkeyMonitor` for the `fn` (Globe) key
/// (ref: verified CGEventTap constants, P20/P21).
///
/// Watches `flagsChanged` events for the secondary-fn modifier, reporting `.down`
/// when it engages and `.up` when it releases, and suppresses the fn event so the
/// OS does not also act on it. If the tap is disabled by timeout or user input it
/// is re-enabled. A `tapIsEnabled` poll lets a supervisor recreate a dead tap.
///
/// L4: exercised on real hardware via the Epic-03 runbook, not in CI.
public final class CGEventTapHotkeyMonitor: HotkeyMonitor {
    public struct HotkeyTapError: Error {
        public let reason: String
    }

    public var onTrigger: ((HotkeyPhase) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Tracks whether fn was last seen engaged, so we emit an edge only on change.
    private var isFnEngaged = false

    public init() {}

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

    public func start() throws {
        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
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
        // The system disables a tap that is too slow or interrupted; re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let fnNowEngaged = event.flags.contains(.maskSecondaryFn)
        guard fnNowEngaged != isFnEngaged else {
            // Not an fn edge (some other modifier changed) — pass it through.
            return Unmanaged.passUnretained(event)
        }
        isFnEngaged = fnNowEngaged
        onTrigger?(fnNowEngaged ? .down : .up)

        // Suppress the fn event so the OS does not also act on it.
        return nil
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
