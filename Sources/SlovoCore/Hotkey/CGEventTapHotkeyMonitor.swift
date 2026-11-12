import CoreGraphics
import Foundation
import os
import Synchronization

/// The push-to-talk key's `CGEventTap`. Observes `flagsChanged` (trigger edges)
/// and `keyDown` (combo interrupts), reduces each event to a `HotkeyInputEvent`,
/// and lets the tap-free `HotkeyDecisionCore` decide the action — emitting
/// `.down`/`.up`/`.cancel` and suppressing or passing the event through. If the
/// tap is disabled by timeout or user input it is re-enabled, the disable is
/// logged, and a held trigger is released via a synthesized `.up`.
///
/// The tap is active, so every key event in the session waits for its callback.
/// The tap therefore runs on a thread of its own: a busy main thread never holds
/// up typing in other apps. Every field the two threads share sits behind one
/// lock, and the compiler refuses any other: the class is `Sendable`, so it can
/// hold no unguarded mutable state.
///
/// Exercised on real hardware via the manual runbook, not in CI; its decision
/// logic is unit-tested through `HotkeyDecisionCore`.
public final class CGEventTapHotkeyMonitor: Sendable {
    public struct HotkeyTapError: Error {
        public let reason: String
    }

    /// An installed tap and the run loop of the thread that serves it. Unchecked
    /// because Core Foundation does not mark these types `Sendable`, yet "the
    /// functions in Core Foundation are generally thread-safe and can be called from
    /// any thread" (archived guide, Threading Programming Guide, "Run Loop
    /// Management", updated 2014-07-15). Only `stop()` calls them off the tap thread.
    private struct InstalledTap: @unchecked Sendable {
        let port: CFMachPort
        let runLoop: CFRunLoop
    }

    private struct State {
        var decisionCore: HotkeyDecisionCore
        var onTrigger: (@Sendable (HotkeyPhase) -> Void)?
        var tap: InstalledTap?
    }

    private static let diagnosticLog = Logger(subsystem: "com.slovo.app", category: "hotkey")

    private let state: Mutex<State>

    public init(configuration: HotkeyConfiguration) {
        state = Mutex(State(decisionCore: HotkeyDecisionCore(configuration: configuration)))
    }

    /// Invoked on the tap thread for each hotkey edge, in the order the keys
    /// moved; `.down` ⇒ Start, `.up` ⇒ Stop.
    public var onTrigger: (@Sendable (HotkeyPhase) -> Void)? {
        get { state.withLock { $0.onTrigger } }
        set { state.withLock { $0.onTrigger = newValue } }
    }

    /// Applies a live key change in place. The event mask is key-independent, so
    /// only the decision core changes — no tap teardown, no failure window, no
    /// pipeline rebuild. A change made during a hold applies when that hold closes,
    /// so its release still reaches `onTrigger`.
    public func reconfigure(configuration: HotkeyConfiguration) {
        state.withLock { $0.decisionCore.reconfigure(to: configuration) }
    }

    /// Starts the tap thread and returns once it has installed the tap, or throws
    /// when the tap could not be created.
    public func start() throws {
        let installed = DispatchSemaphore(value: 0)
        // The thread's closure holds `self` until its run loop exits, and the
        // callback runs only inside that run loop, so the unretained `refcon` can
        // never outlive the monitor.
        let thread = Thread { [self] in
            serveTap(reportingTo: installed)
        }
        thread.name = "com.slovo.app.hotkey-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        installed.wait()
        guard state.withLock({ $0.tap != nil }) else {
            throw HotkeyTapError(reason: "CGEvent.tapCreate returned nil (Input Monitoring not granted?)")
        }
    }

    /// Removes the tap. Invalidating the port takes its source off the tap
    /// thread's run loop, so `CFRunLoopRun` returns even when the thread has not
    /// reached it yet, and `CFRunLoopStop` wakes it when it is waiting.
    public func stop() {
        state.withLock { state in
            guard let tap = state.tap else { return }
            CGEvent.tapEnable(tap: tap.port, enable: false)
            CFMachPortInvalidate(tap.port)
            CFRunLoopStop(tap.runLoop)
            state.tap = nil
        }
    }

    /// The tap thread's whole life: create the tap on this thread, add it to this
    /// thread's run loop, report back to `start()`, and serve events until `stop()`.
    private func serveTap(reportingTo installed: DispatchSemaphore) {
        // keyDown joins flagsChanged so the tap can observe an interrupting key
        // press and cancel a passthrough-modifier hold.
        let eventMask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        )
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            installed.signal()
            return
        }
        let runLoop: CFRunLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        state.withLock { $0.tap = InstalledTap(port: port, runLoop: runLoop) }
        installed.signal()
        CFRunLoopRun()
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

        // The edge is sent outside the lock, so the receiver never runs under it.
        let (decision, onTrigger) = state.withLock { state in
            let decision = state.decisionCore.handle(inputEvent)
            if case .resync = decision, let tap = state.tap {
                CGEvent.tapEnable(tap: tap.port, enable: true)
            }
            return (decision, state.onTrigger)
        }

        switch decision {
        case .start(let suppress, let mode):
            onTrigger?(.down(mode))
            return suppress ? nil : Unmanaged.passUnretained(event)
        case .stop(let suppress, let mode):
            onTrigger?(.up(mode))
            return suppress ? nil : Unmanaged.passUnretained(event)
        case .translateLatched:
            // Live mid-hold latch: report it so the glyph can switch, and pass the
            // translate key through so it keeps working as a normal modifier.
            onTrigger?(.translateLatched)
            return Unmanaged.passUnretained(event)
        case .interruptCancel:
            onTrigger?(.cancel)
            // The real combo (e.g. Right ⌘ + C) must proceed untouched.
            return Unmanaged.passUnretained(event)
        case .resync(let synthesizedStop):
            // The unified log keeps numbers unredacted and redacts dynamic strings
            // (man page `os_log(3)`, revision "June 2, 2016"): the Bool is logged as a
            // number, and the cause is a literal of its own arm.
            let releasedHold = synthesizedStop != nil
            if type == .tapDisabledByTimeout {
                Self.diagnosticLog.notice("key tap disabled by timeout, re-enabled; open hold released: \(releasedHold)")
            } else {
                Self.diagnosticLog.notice("key tap disabled by user input, re-enabled; open hold released: \(releasedHold)")
            }
            if let synthesizedStop {
                // The emergency stop keeps the dead hold's mode, so a translate
                // dictation is not silently downgraded on the way out.
                onTrigger?(.up(synthesizedStop))
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
