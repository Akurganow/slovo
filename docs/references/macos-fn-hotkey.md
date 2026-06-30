# macOS fn / Globe hotkey

## Purpose

slovo is a menu-bar push-to-talk dictation app for Apple Silicon. It needs to use the
`fn` / Globe key as a **global** push-to-talk trigger (hold to record, release to
transcribe) while **suppressing** the OS default `fn` action (the emoji picker / system
Dictation that macOS shows on a `fn` press). Only a CoreGraphics **active event tap** can
both observe the `fn` key system-wide *and* swallow it; a passive `NSEvent` monitor can
observe but cannot suppress.

## Key APIs

### CoreGraphics event tap (active, can suppress)

```swift
// CGEventTapCreate / CGEvent.tapCreate — returns a CFMachPort, or nil on failure.
static func tapCreate(
    tap: CGEventTapLocation,        // .cgSessionEventTap | .cghidEventTap | .cgAnnotatedSessionEventTap
    place: CGEventTapPlacement,     // .headInsertEventTap | .tailAppendEventTap
    options: CGEventTapOptions,     // .defaultTap (can modify/suppress) | .listenOnly (read-only)
    eventsOfInterest: CGEventMask,  // bitmask of (1 << CGEventType.rawValue)
    callback: CGEventTapCallBack,   // C function pointer, see below
    userInfo: UnsafeMutableRawPointer?
) -> CFMachPort?
```

- **`CGEventTapCallBack`** signature:
  `(CGEventTapProxy, CGEventType, CGEvent, UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>?`
  Return the (passed/modified) event to let it through, or **return `nil` to suppress** it.
  Because it is a C function pointer it captures nothing; pass `self` via `userInfo` and
  bridge it back with `Unmanaged.fromOpaque`.
- **Run-loop attachment:** wrap the port with
  `CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)` → returns a
  `CFRunLoopSource`; add it with `CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)`.
- **Enable / health:** `CGEvent.tapEnable(tap: CFMachPort, enable: Bool)` and
  `CGEvent.tapIsEnabled(tap: CFMachPort) -> Bool`. The system can silently disable a tap
  (see gotchas) and delivers `tapDisabledByTimeout` / `tapDisabledByUserInput` events to
  the callback — re-enable on those.

### Detecting `fn` — flag and event

- `fn` is a **modifier**, so it arrives as a `CGEventType.flagsChanged` event (there is no
  separate keyUp/keyDown for it). Press vs. release is derived from whether the flag is
  present in the new flag set.
- The flag is `CGEventFlags.maskSecondaryFn` (Objective-C `kCGEventFlagMaskSecondaryFn`),
  raw value **`0x800000`** (8388608). Press = flag now set; release = flag now clear.

`CGEventFlags` raw values (from CoreGraphics `CGEventTypes.h`, mirrored below):

| Case               | Hex        | Decimal  | Meaning            |
|--------------------|------------|----------|--------------------|
| `maskAlphaShift`   | `0x10000`  | 65536    | Caps Lock          |
| `maskShift`        | `0x20000`  | 131072   | Shift              |
| `maskControl`      | `0x40000`  | 262144   | Control            |
| `maskAlternate`    | `0x80000`  | 524288   | Option / Alt       |
| `maskCommand`      | `0x100000` | 1048576  | Command            |
| `maskNumericPad`   | `0x200000` | 2097152  | Numeric keypad     |
| `maskHelp`         | `0x400000` | 4194304  | Help               |
| **`maskSecondaryFn`** | **`0x800000`** | **8388608** | **fn / Globe** |

`CGEventTapLocation`: `cghidEventTap` = 0, `cgSessionEventTap` = 1,
`cgAnnotatedSessionEventTap` = 2. `CGEventTapPlacement`: `headInsertEventTap` = 0,
`tailAppendEventTap` = 1. `CGEventTapOptions`: `defaultTap` = 0, `listenOnly` = 1.
Disable events: `tapDisabledByTimeout` (rawValue `0xFFFFFFFE`),
`tapDisabledByUserInput` (rawValue `0xFFFFFFFF`).

### Lighter alternative — `NSEvent` global monitor (cannot suppress)

```swift
class func addGlobalMonitorForEvents(
    matching mask: NSEvent.EventTypeMask,   // e.g. .flagsChanged
    handler: @escaping (NSEvent) -> Void
) -> Any?
```

- Receives **copies** of events posted to *other* apps; the handler returns `Void`, so it
  **cannot modify or swallow** the event — the OS default `fn` action still fires.
- Read `event.modifierFlags.contains(.function)` to detect `fn`.
- Use this only if slovo is willing to let macOS also act on `fn` (not acceptable for
  push-to-talk, where suppression is required). It is simpler and lower-risk than a tap.

## Minimal Swift example — active suppressing tap on `fn` press/release

```swift
import CoreGraphics
import Foundation

final class FnHotkeyTap {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isFnDown = false

    /// `onChange(true)` = fn pressed, `onChange(false)` = fn released.
    var onChange: ((Bool) -> Void)?

    func start() {
        // Only flagsChanged is needed; fn is a modifier, not a key event.
        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            let me = Unmanaged<FnHotkeyTap>.fromOpaque(userInfo!).takeUnretainedValue()

            // Re-enable if the system disabled the tap (timeout / user input).
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }

            if type == .flagsChanged {
                let fnDown = event.flags.contains(.maskSecondaryFn)
                if fnDown != me.isFnDown {
                    me.isFnDown = fnDown
                    me.onChange?(fnDown)
                    // Suppress the OS default fn action (emoji / dictation).
                    return nil
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,        // session level is enough for keyboard input
            place: .headInsertEventTap,     // run before other taps so we can suppress
            options: .defaultTap,           // .defaultTap is REQUIRED to suppress
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // nil => permission missing or denied (see permissions gotchas).
            return
        }
        self.tap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        runLoopSource = nil
        tap = nil
    }
}
```

> Note: `flagsChanged` reports the *new* combined flag set, not which physical key toggled.
> Track previous state (`isFnDown`) to distinguish a real `fn` press/release from other
> modifier changes, and to avoid emitting duplicate events.

## slovo gotchas

- **Suppression requires `.defaultTap`.** `.listenOnly` taps cannot return `nil` to
  swallow the event — the emoji picker / Dictation will still pop up. Suppress only the
  `fn` event itself; pass everything else through untouched (`Unmanaged.passUnretained`).
- **Permissions differ by tap mode** (this is the single biggest trap — and the exact
  rule is *not* crisply documented by Apple, so treat the per-mode mapping below as
  practitioner-observed behavior, not a guaranteed contract):
  - **Practitioner-observed:** an **active / suppressing** tap (`.defaultTap`) needs
    **Accessibility** — `tapCreate` with `kCGEventTapOptionDefault` is widely reported to
    return `nil`/NULL until Accessibility is granted, and production keyboard remappers
    (e.g. Karabiner-Elements) require Accessibility and treat Input Monitoring as covered
    by it. Check/prompt via `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`.
  - A **passive** read-only tap (`.listenOnly`) or an `NSEvent` keyboard monitor requires
    **Input Monitoring**, checked/requested via `CGPreflightListenEventAccess()` /
    `CGRequestListenEventAccess()`.
  - **Caveat (conflicting Apple DTS guidance):** Quinn (Apple DTS) states that for a plain
    `CGEventTap` you should use `CGPreflightListenEventAccess` / `CGRequestListenEventAccess`
    and that you "only need the Accessibility privilege if you're doing other stuff with
    Accessibility APIs" — i.e. DTS does **not** endorse the "active tap ⇒ Accessibility"
    rule as such (https://developer.apple.com/forums/thread/744440). Because the documented
    behavior is ambiguous and has shifted across macOS releases, slovo should **preflight
    both** permissions and degrade gracefully rather than rely on one mapping.
  - In practice slovo most likely needs Accessibility (because it suppresses) and it is good
    UX to also preflight Input Monitoring. `IOHIDCheckAccess` /
    `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` are the lower-level IOKit equivalents
    of the `CGPreflight/RequestListenEventAccess` pair (both map to the same TCC
    `kTCCServiceListenEvent` Input Monitoring grant). `IOHIDCheckAccess` returns an
    `IOHIDAccessType` (`granted`/`denied`/`unknown`); `IOHIDRequestAccess` returns a `Bool`.
  - **Activation-policy trap:** a tap can also fail to be created if the app uses
    `LSBackgroundOnly` (`NSApplicationActivationPolicyProhibited`). Apple DTS recommends
    `LSUIElement` / `NSApplicationActivationPolicyAccessory` for menu-bar agents like slovo
    (https://developer.apple.com/forums/thread/758554).
  - `tapCreate` returning `nil` almost always means the required permission is not yet
    granted. Preflight, and if missing, prompt and guide the user to System Settings; the
    permission usually takes effect without relaunch, but Accessibility historically may
    require a relaunch to take effect.
- **Re-enable on disable.** The system disables a tap that is too slow (delivers a
  `tapDisabledByTimeout` event) or after certain user input (`tapDisabledByUserInput`),
  and also commonly after sleep/wake. Handle both in the callback and call
  `CGEvent.tapEnable(tap:enable:true)`. Keep the callback fast (just flip state and signal;
  do transcription work off the tap thread) to avoid timeouts.
- **Code-signing caveat (silent disable).** TCC permission grants are keyed to the
  binary's **code identity**. Re-signing (dev builds, ad-hoc signing, changing the signing
  identity) makes macOS treat the app as a new identity and re-evaluate the grant. A
  re-signed app launched via Launch Services (Finder/Dock/`open`) can have a tap that is
  non-nil and reports `tapIsEnabled == true` yet **never receives callbacks** — and the
  disable callback may not fire. Mitigations: ship with a **stable signing identity**, and
  add a runtime **health check** (poll `CGEvent.tapIsEnabled` every few seconds; if false,
  `tapEnable`; if that fails, tear down and recreate the tap).
- **Run loop is required.** The tap is inert until its `CFRunLoopSource` is added to a
  running run loop. On the main thread the app run loop suffices; if you create the tap on
  a background thread, ensure that thread runs its run loop.

## Full sources

Apple Developer (canonical API truth):

- `CGEvent.tapCreate(...)` — https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)
- `CGEventFlags` — https://developer.apple.com/documentation/coregraphics/cgeventflags
- `CGEventFlags.maskSecondaryFn` — https://developer.apple.com/documentation/coregraphics/cgeventflags/masksecondaryfn
- `CGEventType.tapDisabledByTimeout` — https://developer.apple.com/documentation/coregraphics/cgeventtype/tapdisabledbytimeout
- `CGPreflightListenEventAccess()` — https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess()
- `CGRequestListenEventAccess()` — https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess()
- `NSEvent.addGlobalMonitorForEvents(matching:handler:)` — https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)
- Quartz Event Services Reference (event tap lifecycle, disable-by-timeout) — https://leopard-adc.pepas.com/documentation/Carbon/Reference/QuartzEventServicesRef/QuartzEventServicesRef.pdf

Header-accurate enum/flag values (mirror of CoreGraphics `CGEventTypes.h`):

- `objc2-core-graphics` generated `CGEventTypes.rs` — https://docs.rs/objc2-core-graphics/latest/src/objc2_core_graphics/generated/CGEventTypes.rs.html

Permission / code-signing behavior:

- Apple Forums — "Investigate using CGEvent.tapCreate for global hotkeys" (Quinn/DTS: Input Monitoring vs CGEventTap) — https://github.com/nikitabobko/AeroSpace/issues/1012
- Apple Forums — "Determining if Accessibility (for CGEventTap) is granted" — https://developer.apple.com/forums/thread/744440
- Daniel Raffel — "CGEvent Taps and Code Signing: The Silent Disable Race" — https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/

Open-source precedents (hold-a-modifier push-to-talk dictation, native Swift, Apple Silicon).
Note: neither hard-codes `fn` — both make the trigger key **configurable**, which is a
useful pattern for slovo to copy (offer `fn` as a default but allow a fallback, since some
external keyboards do not report `fn` reliably):

- Parakey (rcourtman/parakey) — CGEventTap hotkey + Parakeet/ANE, ~100 ms key-release-to-text.
  Default trigger is **Right Option** (not `fn`); configurable to Right Control / Right
  Command / F-keys / custom — https://github.com/rcourtman/parakey
- Speak2 (zachswift615/speak2) — hold the trigger to record, release to transcribe. Default
  is **`fn`**, configurable (Right Option / Right Command / Hyper / Ctrl+Option+Space /
  custom) — https://github.com/zachswift615/speak2
- pqrs-org/osx-event-observer-examples — canonical NSEvent vs CGEventTap observer examples + permission handling — https://github.com/pqrs-org/osx-event-observer-examples
- Hammerspoon `libeventtap.m` — production re-enable-on-disable pattern — https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/eventtap/libeventtap.m

## Verification

Date: 2026-06-27

Verdict: PARTIAL — all enum/flag integers, the `tapCreate` signature, the
`CGEventTapCallBack` signature, and the IOHID equivalence are CONFIRMED correct against
canonical sources; two corrections were applied: (a) the Accessibility-vs-Input-Monitoring
permission distinction was overstated as Apple fact and is contradicted by the one crisp
Apple DTS source — softened to practitioner-observed + caveat; (b) the open-source precedent
descriptions were wrong/incomplete on the trigger key (Parakey defaults to Right Option, not
`fn`; both apps are configurable).

Checked:
- CGEventFlags integer values (`maskAlphaShift`=0x10000 … `maskSecondaryFn`=0x800000,
  `maskCommand`=0x100000, `maskAlternate`=0x80000) — CONFIRMED by two independent header
  sources (objc2 mirror + phracker CGEventTypes.h + search of header values).
- `tapDisabledByTimeout`=0xFFFFFFFE, `tapDisabledByUserInput`=0xFFFFFFFF — CONFIRMED
  (objc2 mirror + phracker header explicit hex).
- `CGEventTapOptions` `defaultTap`=0 / `listenOnly`=1; `CGEventTapLocation` 0/1/2;
  `CGEventTapPlacement` 0/1 — CONFIRMED (objc2 mirror + phracker header).
- `CGEvent.tapCreate(tap:place:options:eventsOfInterest:callback:userInfo:) -> CFMachPort?`
  parameter labels, types, return — CONFIRMED (Apple JSON endpoint).
- `CGEventTapCallBack` = `(CGEventTapProxy, CGEventType, CGEvent, UnsafeMutableRawPointer?)
  -> Unmanaged<CGEvent>?` (C: returns NULL to delete event) — CONFIRMED (Apple JSON endpoint
  + phracker header typedef).
- `IOHIDCheckAccess` / `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` as IOKit
  equivalents of `CGPreflight/RequestListenEventAccess` (both → TCC `kTCCServiceListenEvent`
  Input Monitoring) — CONFIRMED (multiple sources; `kIOHIDRequestTypeListenEvent`=1,
  `IOHIDCheckAccess` → `IOHIDAccessType` granted/denied/unknown).
- Accessibility-vs-Input-Monitoring per tap mode — PARTIAL: practitioner-observed (active
  `.defaultTap` ⇒ Accessibility) holds in real apps (Karabiner, AeroSpace) but is NOT Apple
  doctrine and is explicitly undercut by Quinn/DTS thread 744440. Caveat added.
- Parakey/Speak2 trigger keys — CORRECTED from live READMEs.

Corrections (before → after):
- Permissions: "active/suppressing tap (`.defaultTap`) **requires** Accessibility" stated as
  fact → reframed as practitioner-observed, with explicit DTS-conflict caveat (thread 744440)
  and a "preflight both" recommendation; added IOHID return-type detail and the
  `LSBackgroundOnly`/activation-policy failure path (thread 758554).
- Precedents: "fn push-to-talk … Parakey — CGEventTap hotkey" / "Speak2 — hold `fn`
  (configurable)" → Parakey **defaults to Right Option** (configurable), Speak2 defaults to
  `fn` (configurable); reframed the section as "hold-a-modifier" with configurable triggers.

URLs validated (fetched/searched this date):
- https://developer.apple.com/tutorials/data/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:).json (tapCreate signature)
- https://developer.apple.com/tutorials/data/documentation/coregraphics/cgeventtapcallback.json (callback signature)
- https://docs.rs/objc2-core-graphics/latest/src/objc2_core_graphics/generated/CGEventTypes.rs.html (all integer values)
- https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX10.8.sdk/System/Library/Frameworks/CoreGraphics.framework/Versions/A/Headers/CGEventTypes.h (header: disable/option values + callback typedef)
- https://developer.apple.com/forums/thread/744440 (DTS: CGEventTap ⇒ ListenEventAccess, Accessibility only for AX APIs)
- https://developer.apple.com/forums/thread/696673 (IOHIDRequestAccess/IOHIDCheckAccess, kIOHIDRequestTypeListenEvent)
- https://developer.apple.com/forums/thread/758554 (DTS: LSBackgroundOnly/activation-policy tap-creation failure)
- https://github.com/nikitabobko/AeroSpace/issues/1012 (defaultTap⇒Accessibility, listenOnly⇒Input Monitoring; practitioner)
- https://karabiner-elements.pqrs.org/docs/manual/misc/required-macos-settings/ (production: Accessibility covers Input Monitoring)
- https://github.com/rcourtman/parakey (default Right Option, configurable)
- https://github.com/zachswift615/speak2 (default fn, configurable)

Confirmable only on a real macOS SDK / Xcode (not fully verifiable from web sources):
- The exact numeric `CGEventFlags` values are `#define`d in the live `<CoreGraphics/
  CGEventTypes.h>` as references to IOKit `NX_*` constants (`NX_SECONDARYFNMASK`, etc.); the
  phracker header confirms the indirection but the *numeric* expansion was cross-checked only
  via the objc2 mirror and header-value search, not by compiling against the current SDK.
  (Why: Apple's JSON doc endpoints omit raw enum values; they are only materialized at
  compile time. Cross-checked against two independent header sources instead.)
- The empirical "active suppressing tap returns nil without Accessibility" behavior is
  TCC/macOS-version dependent and can only be confirmed by running on a real machine across
  macOS releases. (Why: it is runtime/TCC behavior, not an API contract, and Apple's own
  guidance is inconsistent.)
