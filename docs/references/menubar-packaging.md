# Menu-bar agent app + packaging

## Purpose

loqui is a native Swift macOS dictation tool that lives only in the menu bar (no
Dock icon, no main window) and is driven by a global hotkey. This reference
collects the verified AppKit APIs and packaging/codesigning facts needed to:

1. Show a status item in the system menu bar with state-dependent icons
   (idle / recording / processing / error) and a dropdown menu.
2. Configure the process as a background **agent** (no Dock icon, no app switcher
   entry) via `LSUIElement` / `NSApplication.ActivationPolicy.accessory`.
3. Declare the right `Info.plist` usage-description keys (microphone) and
   understand why Accessibility / Input Monitoring are TCC grants, not plist keys.
4. Package a SwiftPM-built executable into a `.app` bundle.
5. Sign with a **stable** identity so Accessibility / Input-Monitoring grants
   survive rebuilds — the central packaging caveat for loqui.
6. Notarize for distribution (covered briefly).

All symbols below were verified against Apple Developer documentation; the few
that could not be confirmed against a primary Apple source are marked
`[UNVERIFIED]`. Canonical URLs are listed under **Full sources**.

---

## Menu-bar status item (`NSStatusItem`)

A status item is owned by the system-wide status bar. You never allocate it
directly; you ask the shared `NSStatusBar` to vend one.

- `NSStatusBar.system` — the system-wide status bar in the menu bar
  (Objective-C name: `+[NSStatusBar systemStatusBar]`).
- `statusItem(withLength:)` — returns a newly created `NSStatusItem` allotted a
  given width. The status bar does **not** retain the item, so store a strong
  reference (e.g. a property on your `AppDelegate`).
- Length constants:
  - `NSStatusItem.variableLength` (Obj-C `NSVariableStatusItemLength`) — width
    grows to fit contents; use for text.
  - `NSStatusItem.squareLength` (Obj-C `NSSquareStatusItemLength`) — width equals
    the bar thickness; use for a single icon. loqui wants `squareLength` (icon
    only) or `variableLength` if it ever shows text.

The visible control is the item's **button**, an `NSStatusBarButton` exposed via
the optional `button` property. Set its `image` and/or `title`; attach a `menu`
to the status item for a click-to-open dropdown.

```swift
import AppKit

final class StatusController {
    private var statusItem: NSStatusItem!   // strong ref — bar does not retain

    func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "loqui")
            button.image?.isTemplate = true   // adapt to light/dark menu bar
        }
        statusItem.menu = buildMenu()
    }

    // State-dependent icon swap (idle / recording / processing / error).
    func setState(_ symbol: String, description: String) {
        statusItem.button?.image = NSImage(systemSymbolName: symbol,
                                           accessibilityDescription: description)
        statusItem.button?.image?.isTemplate = true
    }
}
```

Notes:
- `NSImage(systemSymbolName:accessibilityDescription:)` lets loqui map each state
  to an SF Symbol (e.g. `mic`, `mic.fill`, `waveform`, `exclamationmark.triangle`).
  Mark template images so the system tints them for menu-bar contrast.
- For the four loqui states, the simplest design is one status item whose button
  `image` is swapped on state change; no API beyond the above is required.
- Apple documents the `menu` property as "The pull-down menu displayed when the
  user clicks the status item." So if you assign `statusItem.menu`, clicking the
  button opens that menu. If you instead want custom click vs. right-click
  behavior, leave `menu` unset and wire `button.target` / `button.action`,
  building/popping a menu manually. `[UNVERIFIED]` Apple does not publish an
  explicit sentence stating the button's target-action is suppressed when a
  menu is set — that precedence is community-reported behavior, not a quoted
  Apple guarantee; treat "menu set ⇒ action not delivered" as observed, not
  documented.

---

## Agent app config (`LSUIElement` / `.accessory`)

A menu-bar-only ("agent") app must not show a Dock icon, must not appear in the
Force Quit window, and must not take over the menu bar with an app menu/main
window. Two mechanisms, used together:

1. **`LSUIElement` Info.plist key** (human name "Application is agent
   (UIElement)") — a Boolean. When `true`, the app runs as a background agent:
   no Dock icon, not in the Cmd-Tab switcher. It may still bring UI forward.

   ```xml
   <key>LSUIElement</key>
   <true/>
   ```

2. **Activation policy** — `NSApplication.ActivationPolicy.accessory`. Per Apple,
   when `LSUIElement` is `true`, `NSApp.activationPolicy()` reports `.accessory`.
   You can also set it at runtime; `.regular` would override `LSUIElement` and
   bring back the Dock icon, so do not set `.regular` for loqui.

Minimal app entry (no Storyboard, no main window):

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let status = StatusController()
    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)   // belt-and-suspenders with LSUIElement
        status.install()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

`ActivationPolicy` values (Apple's abstracts):
- `.regular` — "an ordinary app that appears in the Dock and may have a user
  interface."
- `.accessory` — "doesn't appear in the Dock and doesn't have a menu bar, but it
  may be activated programmatically or by clicking on one of its windows."
- `.prohibited` — "doesn't appear in the Dock and may not create windows or be
  activated."

loqui = `.accessory`.

---

## Info.plist keys

Required / relevant keys for loqui's `Info.plist`:

| Key | Type | Purpose |
| --- | --- | --- |
| `CFBundleIdentifier` | String | Stable bundle id, e.g. `com.<you>.loqui`. TCC ties grants to (bundle id + code signature); keep it constant. |
| `CFBundleName` / `CFBundleExecutable` | String | Bundle and executable names. |
| `CFBundleShortVersionString` / `CFBundleVersion` | String | Version metadata. |
| `LSMinimumSystemVersion` | String | Minimum macOS. |
| `LSUIElement` | Boolean (`true`) | Run as menu-bar agent (see above). |
| `NSMicrophoneUsageDescription` | String | **Required** to record audio. Shown in the system permission prompt the first time loqui touches the mic via `AVCaptureDevice` / Core Audio. Omitting it crashes the app on first mic access. |
| `NSPrincipalClass` | String | `NSApplication` for an AppKit app. |

**Important — TCC grants vs. Info.plist keys.** Accessibility and Input
Monitoring are **not** unlocked by `Info.plist` keys. They are TCC privacy
permissions the *user* grants in **System Settings → Privacy & Security →
Accessibility / Input Monitoring**:

- **Accessibility** — gates `AXIsProcessTrusted()` and synthesizing/observing
  events via a default `CGEventTap` (and posting events). Check with
  `AXIsProcessTrusted()`; prompt with `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`.
  There is no programmatic way to grant it — the user must toggle it.
- **Input Monitoring** — gates a *listen-only* `CGEventTap`
  (`CGEventTapOptions.listenOnly`) used to observe a global hotkey. Check it with
  `CGPreflightListenEventAccess()` and request it with
  `CGRequestListenEventAccess()` (the Input-Monitoring counterparts to the
  Accessibility `AXIsProcessTrusted*` calls). Per Apple DTS (Quinn "Eskimo"),
  Input Monitoring "is easily available to sandboxed apps, and even apps
  published on the Mac App Store."

`NSAccessibilityUsageDescription` exists as a plist string for the prompt text
in some configurations, but it does **not** grant the permission. Whether loqui
needs Accessibility, Input Monitoring, or both depends on how it captures the
global hotkey (see loqui gotchas).

---

## Codesign & permission persistence

This is the crux for loqui: **TCC identifies the app by its bundle identifier +
its code signature (its "designated requirement").** If the signature changes
between builds, macOS treats the new build as a *different* app, and previously
granted Accessibility / Input Monitoring / Microphone permissions silently stop
applying — the user has to re-grant them every rebuild.

### Ad-hoc vs. Developer ID

- **Ad-hoc** (`codesign -s -`): no identity, signature is not stable across
  rebuilds. Permissions tend not to persist; hardened runtime is typically
  disabled. Fine for a quick local run, painful for a tool you grant
  Accessibility to and rebuild often.
- **Developer ID Application** certificate: a stable identity. macOS recognizes
  successive builds as the same app, so TCC grants survive rebuilds. This is the
  signing identity loqui should use even for personal local use, precisely so you
  don't re-grant Accessibility on every `swift build`.

### Basic `codesign`

```bash
# Sign the bundle with a stable Developer ID identity + hardened runtime + entitlements
codesign --force --deep --options runtime \
  --entitlements loqui.entitlements \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  loqui.app

# Verify
codesign --verify --deep --strict --verbose=2 loqui.app
codesign --display --entitlements - loqui.app   # inspect entitlements
spctl --assess --type execute --verbose loqui.app   # Gatekeeper assessment
```

- `--options runtime` enables the **Hardened Runtime** (required for
  notarization, and for some TCC behaviors).
- Sign nested code (frameworks, helpers) before the outer bundle; `--deep` is a
  convenience but Apple recommends signing inside-out explicitly for anything
  non-trivial.

### Entitlements relevant to loqui

In `loqui.entitlements` (a plist):

- `com.apple.security.device.audio-input` (Boolean `true`) — "Audio Input
  Entitlement": "indicates whether the app may record audio using the built-in
  microphone and access audio input using Core Audio." Apple's add-path is the
  **Hardened Runtime** capability (Resource Access → Audio Input) — i.e. the
  entitlement for a **notarized / Hardened-Runtime** app shipped outside the Mac
  App Store.
- `com.apple.security.device.microphone` (Boolean `true`) — "indicates whether
  the app may use the microphone." Apple's add-path is the **App Sandbox**
  capability (Hardware → Audio Input) — i.e. the entitlement for a **sandboxed**
  app (Mac App Store). With App Sandbox, mic access generally needs both the
  audio-input and microphone entitlements.

### App Sandbox vs. Accessibility / event taps — a real conflict

**Do not enable App Sandbox if loqui needs the Accessibility permission.**
Verified behavior:

- With `com.apple.security.app-sandbox` enabled, the **Accessibility** prompt
  never appears, the app cannot be added under Privacy → Accessibility, and
  `AXIsProcessTrusted()` always returns `false`. A default `CGEventTap` and
  global event synthesis/observation requiring Accessibility will not work.
- A sandboxed app **can** still use a *listen-only* `CGEventTap`, which needs
  **Input Monitoring** (not Accessibility); Input Monitoring is available to
  sandboxed and Mac App Store apps.

Practical guidance for loqui (a personal/OSS dictation tool distributed outside
the Mac App Store, needing a reliable global hotkey + audio capture):

- **Non-sandboxed + Developer ID + Hardened Runtime.** Skip App Sandbox so
  Accessibility (if needed) works; rely on a Developer ID signature so grants
  persist; enable Hardened Runtime for notarization.
- If loqui only *listens* for a hotkey (listen-only tap), Input Monitoring may
  suffice and you could stay sandboxed — but mixing that with full dictation
  ergonomics is more constrained. Decide based on whether you ever need a
  default (active) event tap.

`com.apple.security.cs.disable-library-validation` (Boolean) — "Disable Library
Validation Entitlement": "indicates whether the app loads arbitrary plug-ins or
frameworks, without requiring code signing." The Hardened Runtime turns on
*library validation* by default, which blocks loading any framework/plug-in/dylib
not signed by Apple or signed with the **same Team ID** as the main executable.
This entitlement removes that restriction; Apple's guidance: "Use the Disable
Library Validation Entitlement if your program loads plug-ins that are signed by
other third-party developers." Note Apple's caveat: "Because library validation
is such an important security-hardening feature, Gatekeeper runs extra security
checks on programs that have it disabled." loqui needs this **only** if it loads
third-party / differently-signed dylibs under Hardened Runtime — do not add it
otherwise. (Doc verified at the `bundleresources/entitlements` path; the earlier
404 was a stale URL, now listed under Full sources.)

---

## Notarization (brief)

Even for a personal/OSS app, notarizing lets the app open on other Macs without
the "unidentified developer" / Gatekeeper block. Requirements: signed with a
**Developer ID Application** cert and **Hardened Runtime** enabled.

```bash
# 1) Store credentials once (App Store Connect app-specific password)
xcrun notarytool store-credentials "loqui-notary" \
  --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"

# 2) Submit a zip/dmg/pkg and wait
ditto -c -k --keepParent loqui.app loqui.zip
xcrun notarytool submit loqui.zip --keychain-profile "loqui-notary" --wait

# 3) Staple the ticket so Gatekeeper works offline
xcrun stapler staple loqui.app
```

`notarytool` uploads to the Apple Notary Service, which scans for malware and
common signing problems and returns a ticket; `stapler` attaches that ticket to
the bundle so Gatekeeper can verify without a network round-trip. Notarization
is required only for distribution to other machines — local-only use can stop at
Developer ID signing.

---

## loqui gotchas

- **Stable signature is non-negotiable.** Sign every build with the same
  Developer ID identity and keep `CFBundleIdentifier` constant, or you will
  re-grant Accessibility / Input Monitoring / Microphone after every rebuild.
  This is the single biggest packaging footgun for a TCC-dependent menu-bar tool.
- **Pick Accessibility vs. Input Monitoring deliberately.** A *default*
  `CGEventTap` (to observe/inject keystrokes actively) needs **Accessibility**
  and is incompatible with App Sandbox. A *listen-only* tap (to observe a hotkey)
  needs **Input Monitoring** and works sandboxed. loqui should choose the minimal
  tap mode its hotkey design requires.
- **Don't sandbox if you need Accessibility.** App Sandbox silently breaks
  Accessibility (`AXIsProcessTrusted()` → `false`, no prompt). Non-sandboxed +
  Developer ID + Hardened Runtime is the pragmatic combo here.
- **`NSMicrophoneUsageDescription` is mandatory.** Without it, first mic access
  via `AVCaptureDevice` / Core Audio crashes the process. The string is shown in
  the permission prompt.
- **SwiftPM executables don't produce a `.app` by default.** `swift build`
  yields a bare Mach-O in `.build/<config>/loqui`. You must construct the bundle
  by hand (or with a build script): create `loqui.app/Contents/{MacOS,Resources}`,
  copy the executable into `Contents/MacOS/loqui`, and write
  `Contents/Info.plist` (with `LSUIElement`, `CFBundleExecutable`, etc.). SwiftPM
  forbids a top-level `Info.plist` *resource*; embedding one in a pure CLI binary
  requires linker-section flags. For a menu-bar app, prefer building the `.app`
  bundle structure explicitly. Bundle layout (verified): executable in
  `Contents/MacOS/`, resources in `Contents/Resources/`, `Info.plist` in
  `Contents/`. (An Xcode app target produces this `.app` automatically and is the
  lower-friction path if you'd rather not script bundling.)
- **`isTemplate` on icons.** Set `NSImage.isTemplate = true` for status-bar
  icons so they render correctly in light/dark menu bars; otherwise state icons
  look wrong in one appearance.
- **Strong-reference the status item.** The status bar does not retain it; a
  local variable will vanish and the icon will disappear.

---

## Full sources

AppKit / status item:
- NSStatusBar — https://developer.apple.com/documentation/appkit/nsstatusbar
- NSStatusItem — https://developer.apple.com/documentation/appkit/nsstatusitem
- statusItem(withLength:) — https://developer.apple.com/documentation/appkit/nsstatusbar/statusitem(withlength:)
- NSStatusItem.squareLength — https://developer.apple.com/documentation/appkit/nsstatusitem/squarelength
- Creating Status Items (archived) — https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/StatusBar/Tasks/creatingitems.html

Agent app / activation policy / Info.plist:
- LSUIElement — https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement
- NSApplication.ActivationPolicy — https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum
- NSStatusBarButton — https://developer.apple.com/documentation/appkit/nsstatusbarbutton
- Launch Services Keys (archived) — https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html
- NSMicrophoneUsageDescription — https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSMicrophoneUsageDescription
- AVCaptureDevice — https://developer.apple.com/documentation/avfoundation/avcapturedevice

Sandbox / entitlements / accessibility:
- Configuring the macOS App Sandbox — https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox
- Audio Input Entitlement (com.apple.security.device.audio-input) — https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.device.audio-input
- Microphone Entitlement (com.apple.security.device.microphone) — https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.microphone
- Disable Library Validation Entitlement (com.apple.security.cs.disable-library-validation) — https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation
- Enabling App Sandbox (archived) — https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html
- App Sandbox + Accessibility / use CGEventTap + Input Monitoring (Apple DTS, Quinn "Eskimo") — https://developer.apple.com/forums/thread/707680
- TCC identifies code via its code signature (Apple DTS, Quinn "Eskimo") — https://developer.apple.com/forums/thread/703188

Codesign / Developer ID / notarization:
- Signing Mac Software with Developer ID — https://developer.apple.com/developer-id/
- SwiftPM resources / bundling — https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package

Secondary references (community, for working Swift examples / TCC behavior — not Apple-canonical):
- macOS Status Bar apps (Peter Arsenault) — https://www.peterarsenault.industries/posts/macos-status-bar-apps/part01/
- Accessibility Permission in macOS (jano.dev) — https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html
- Notarizing macOS Apps with notarytool (tonygo.tech) — https://tonygo.tech/blog/2023/notarization-for-macos-app-with-notarytool

---

## Verification

Date: 2026-06-27
Verdict: PASS

Independent verification against live Apple Developer documentation (JSON
endpoints, since the HTML pages are JS-rendered) and canonical Apple DTS forum
threads. All load-bearing symbols and claims confirmed; two `[UNVERIFIED]`
markers resolved and several quotes tightened to Apple's exact wording.

### Checked (confirmed correct against a primary Apple source)

- `NSStatusBar.system` ("Returns the system-wide status bar located in the menu
  bar."), Obj-C `systemStatusBar`. ✓
- `statusItem(withLength:) -> NSStatusItem` ("Returns a newly created status item
  that has been allotted a specified space within the status bar."). ✓
- `NSStatusItem.variableLength` (`NSVariableStatusItemLength`) and
  `NSStatusItem.squareLength` (`NSSquareStatusItemLength`), both `CGFloat`. ✓
- `NSStatusItem.button` typed `NSStatusBarButton?`; `NSStatusItem.menu` typed
  `NSMenu?` ("The pull-down menu displayed when the user clicks the status
  item."). ✓
- `NSStatusBarButton` inherits from `NSButton` (so `image` / `title` are
  inherited NSButton API). ✓
- `LSUIElement` — "Application is agent (UIElement)", Boolean, "agent app that
  runs in the background and doesn't appear in the Dock." ✓
- `NSApplication.ActivationPolicy` cases `.regular` / `.accessory` /
  `.prohibited` with their Apple abstracts. ✓
- `NSMicrophoneUsageDescription` required ("required if your app uses APIs that
  access the device's microphone"). ✓
- `com.apple.security.device.audio-input` → Apple add-path is Hardened Runtime
  (Resource Access → Audio Input). ✓
- `com.apple.security.device.microphone` → Apple add-path is App Sandbox
  (Hardware → Audio Input). ✓
- `com.apple.security.app-sandbox` is the App Sandbox entitlement; App Sandbox is
  a Mac App Store requirement and restricts access to system resources. ✓
- App Sandbox vs Accessibility: sandboxed apps cannot use the Accessibility
  privilege; the supported path is a `CGEventTap` gated by Input Monitoring,
  which "is easily available to sandboxed apps, and even apps published on the
  Mac App Store" (Apple DTS / Quinn "Eskimo"). ✓
- TCC identifies an app via its code signature ("TCC identifies your code via its
  code signature"); the stored designated requirement (`csreq`) pins bundle id +
  Team ID, so a stable Developer ID/Team ID keeps successive builds recognized as
  the same app (Apple DTS / Quinn "Eskimo"). ✓

### Corrections (before → after)

1. `disable-library-validation` was `[UNVERIFIED]` (cited 404). → Now verified at
   `.../bundleresources/entitlements/com.apple.security.cs.disable-library-validation`;
   filled in the real abstract, the "same Team ID or Apple" default, the
   third-party-plug-in trigger, and Apple's Gatekeeper caveat.
2. "menu set ⇒ button target-action not sent" was stated flatly with a hedge. →
   Re-scoped: Apple documents `menu` as "displayed when the user clicks the
   status item" but publishes no sentence suppressing target-action; relabeled
   the suppression as community-observed, not an Apple guarantee (`[UNVERIFIED]`
   retained narrowly on that one point).
3. ActivationPolicy one-liner → replaced with Apple's exact case abstracts.
4. Entitlement split wording → tied each entitlement to Apple's actual Xcode
   add-path (audio-input = Hardened Runtime; microphone = App Sandbox).
5. Listen-only tap → added the canonical Input-Monitoring APIs
   `CGPreflightListenEventAccess()` / `CGRequestListenEventAccess()` and the DTS
   quote.

### URLs validated (HTTP 200 via JSON endpoint or live forum page)

- nsstatusitem, nsstatusbar, nsstatusbarbutton, lsuielement,
  nsmicrophoneusagedescription (data.documentation JSON). ✓
- nsapplication/activationpolicy-swift.enum (JSON). ✓
- entitlements: device.audio-input, device.microphone,
  cs.disable-library-validation (JSON). ✓
- xcode/configuring-the-macos-app-sandbox (JSON). ✓
- forums/thread/707680 (sandbox + Accessibility, DTS) and forums/thread/703188
  (TCC ↔ code signature, DTS). ✓
- Stale/removed: the original
  `.../security/com.apple.security.cs.disable-library-validation` path 404s; the
  current doc lives under `.../bundleresources/entitlements/...` (now in sources).

### Still unverifiable (with reason)

- "Setting `statusItem.menu` suppresses the button's target-action." Apple
  documents that the menu shows on click but states no target-action precedence.
  Left as `[UNVERIFIED]` — community-reported behavior only.
- "Ad-hoc signatures cause TCC re-grants on every rebuild." Directionally
  supported (TCC keys off the code signature; ad-hoc signatures are unstable and
  can't carry an App ID), but Apple publishes no single sentence asserting the
  ad-hoc-specific re-grant; the practical claim rests on the verified
  signature-identity mechanism plus community reports.
