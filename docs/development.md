# Development

## Requirements

- Apple Silicon Mac.
- Xcode 26.4 or newer, the first release carrying the Swift 6.3 toolchain, which
  needs macOS 26.2 or newer on the build machine. The shipped app runs on
  macOS 15 (Sequoia) or newer.
- Swift Package Manager.

## Build

```sh
swift build --disable-automatic-resolution
```

## Run

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  Scripts/build_and_run.sh --verify
```

The development run script rebuilds the `slovo` product, stages
`.build/dev-run/Slovo.app`, signs it with a stable local code-signing identity
and the app entitlements, opens the menu-bar app, and verifies that the `slovo`
process is running. Stable signing is required for macOS TCC permission
persistence; pass the identity explicitly so a different certificate cannot be
selected implicitly. Ad-hoc builds are not valid for user testing.

## Test

```sh
swift test --disable-automatic-resolution
```

Use focused tests while iterating:

```sh
swift test --filter AppShellPackagingTests --disable-automatic-resolution
```

## Full Gate

Run the full local gate before committing or opening a pull request:

```sh
Scripts/diagnose.sh
```

The gate runs build, tests, a cleanup-benchmark CLI smoke check, and strict
lint as separate stages. This keeps one failure from hiding another.

## Lint And Static Checks

```sh
Scripts/lint.sh
```

The lint script runs:

- explicit target dependency import checks
- shell syntax checks
- plist and entitlements linting
- strict SwiftLint
- SwiftLint analyzer checks backed by a compiler log

## Gate Self-Test

The gate has an intentional red-path check:

```sh
SLOVO_GATE_SELFTEST=red swift test --disable-automatic-resolution
```

This command is expected to fail. It proves the gate can go red when armed.

## Cleanup Benchmark

Compare cleanup candidates with the non-product benchmark executable. A full
shortlist run takes a long time, so the preferred way to launch it is the
detached runner, which survives the terminal and the IDE:

```sh
Scripts/run-cleanup-benchmark.sh                 # full shortlist, 10 repetitions
REPETITIONS=3 Scripts/run-cleanup-benchmark.sh   # cheaper run
PROVIDERS=passthrough Scripts/run-cleanup-benchmark.sh   # zero-network smoke
```

All state lands in `.build/benchmark-runs/<stamp>/` (`status`, `run.log` with a
heartbeat, `report.csv` at the end, `benchmark.pid` to abort). The CLI prints
its report only when the whole run completes, so an empty `report.csv` while
`status` is `RUNNING` is normal — watch `run.log`. For a one-off custom run,
invoke `swift run slovo-cleanup-benchmark` with the same `--providers` /
`--repetitions` flags directly.

The benchmark reads API keys from environment variables or the optional env file,
not from Keychain. It prints aggregate latency, quality counts, and optional
failure-code counts only; transcripts and cleaned output stay out of the report.
OpenRouter candidates require `OPENROUTER_API_KEY`; `passthrough` is the local
baseline and does not read network credentials.

See [cleanup-benchmark.md](references/cleanup-benchmark.md) for sample-file
format and benchmark reporting notes.

## Packaging

Published releases are fully automated (see [release-ci.md](release-ci.md)); this
local packaging is only for verifying a build before it is merged.

Packaging runs in two phases (`app`, then `dmg`); use a stable signing identity:

```sh
SIGNING_IDENTITY="Developer ID Application: Alexander Kurganov (ZN8H5SF4R7)" Scripts/sign-and-notarize.sh app
```

The script refuses ad-hoc signing unless `ALLOW_AD_HOC_SIGNING=1` is set. See
[release-checklist.md](release-checklist.md) for the full flow; stapling the
notarization ticket is the only manual step.

## Repository Hygiene

- Keep repository artifacts in English.
- Do not commit local databases, seed files, dotenv files, signing keys, tokens,
  or credential bundles.
- Keep workflow scratch notes outside Git.
- Update public docs when setup, privacy, packaging, or cleanup behavior changes.

## Manual hotkey checks (hardware-only)

The `CGEventTap` is exercised by hand — the decision logic is unit-tested via
`HotkeyDecisionCore`, but the live tap is not in CI. After changing the hotkey
tap, verify on a real keyboard:

- **fn (default):** hold fn, speak, release — text is inserted; the fn press is
  suppressed (the Globe/Emoji picker never appears).
- **fn conflict notice:** with the fn trigger selected and Slovo left running, set
  "Press 🌐 key to" in System Settings ▸ Keyboard to anything but "Do Nothing",
  then REOPEN the dropdown — the remedy line is there, directly under the hold
  hint. Set it back to "Do Nothing", reopen once more, and the line is gone. No
  relaunch and no settings change in Slovo: the notice is re-read from the system
  on every menu open.
- **fn release on an external keyboard:** hold fn, press and release other
  modifiers mid-hold, then release fn — the session ends on the fn release and
  never earlier, and never stays stuck recording.
- **Each side of ⌘, ⌥, ⇧ (six choices):** select one in Settings → General, then
  hold that exact key alone to dictate; the modifier still works normally
  system-wide (it is not suppressed), and the SAME modifier on the other side must
  NOT dictate. ⌃ is offered too, as a single entry standing for both Control keys.
- **Cross-side release:** with (say) Right ⌥ selected, hold Right ⌥ and speak,
  press and hold Left ⌥ mid-hold, then release Right ⌥ — the session must END on that
  release even though Left ⌥ still holds the ⌥ bit (the recording glyph leaves
  the recording state and the dictated text inserts), never staying stuck
  recording.
- **Retired Right ⌃:** an install that had Right ⌃ selected resets to defaults on
  first launch of this build, so the trigger reads fn.
- **Interrupt:** hold the selected modifier and press another key mid-hold
  (e.g. Right ⌘ then C) — dictation is cancelled silently (nothing inserted, no
  error, menu-bar glyph returns to idle) and the real shortcut still fires.
- **Live change:** switch the key in Settings → General while idle — the new key works
  on the next dictation with no "Preparing Speech Model" pulse.
- **Translate key, additional (the default):** hold the push-to-talk key and press
  the translate key (⌃ by default) at any point before releasing — the dictation is
  translated into the configured target (menu bar / Settings → Cleanup), and the
  menu-bar recording glyph switches to Pokoji `Ⱂ` live, at that moment; a hold
  without it is not translated and keeps the plain recording glyph.
- **Additional key already down:** with ⌃ (or fn) as the translate key, hold it
  BEFORE the push-to-talk key and dictate — it counts, and `Ⱂ` shows from the
  start. With a sided ⌘/⌥/⇧ as the translate key the same sequence does NOT
  translate: only its press during the hold is visible to Slovo, which is what the
  README and AGENTS.md say.
- **Translate key, standalone:** turn "Use as additional key" off in Settings →
  General, then hold the translate key alone — it dictates and always translates,
  showing `Ⱂ` from key-down, while the push-to-talk key still dictates plainly.
- **Two keys, one pool:** in Settings → General the key selected in one picker
  reads greyed and unselectable in the other, so the two can never collide; the
  translate row shows `<push-to-talk key> +` before its dropdown only while the
  key is additional. The menu-bar dropdown's second header line tracks both
  settings ("Add ⌃ to translate" / "Hold ⌃ to translate").

## Manual About-window check (UI-only)

The About window is presented through AppKit and is not exercised in CI. After
changing it, verify by hand:

- **Single instance:** open **About Slovo** from the menu bar, then open it again —
  the same window is focused, not a second copy. The version line and the
  push-to-talk keycap match the current build and the configured key.
- **Dev-build marker:** on a dev build (`Scripts/build_and_run.sh`) the header
  version line ends with the Glagolitic capital Dobro `Ⰴ` — the marker stamped as
  the `SlovoDevBuild` Info.plist key by the launcher. A release build shows the
  plain `Version <version> (<build>)` line with no marker; the key never exists in
  a CI-packaged artifact.

## Manual auto-update checks (release-only)

The silent Sparkle pipeline is not exercised in CI (out-of-process installer,
real signatures). Before the FIRST Sparkle-enabled release ships, verify by hand
on the dev Mac:

- **Silent update:** install a previous release build into `/Applications`,
  publish a newer test release, then launch the old build. Within the hourly
  window it downloads silently — no window, no notification — and the dropdown's
  always-visible update row shows "Checking…" during the check, "Downloading
  v<next>", then the hybrid "Update ready — v<next>" row (grey status line;
  "Restart" in white under highlight), while the resting menu-bar glyph switches
  to Nash "Ⱀ" (U+2C10).
- **Both apply paths:** clicking **Restart** installs and relaunches into the new
  version; ignoring it and Quitting normally installs on the way out, so the next
  launch is the new version. The app never restarts on its own.
- **Toggle off:** with Settings → General "Automatically install updates" off, no
  scheduled appcast fetch and no download happen on their own; the menu-bar
  "Check for Updates…" row still runs a check, but only when clicked.
- **Mandatory negative Team-ID check (before the first release):** feed the
  installed framework a correctly-EdDSA-signed DMG whose bundle is signed by a
  DIFFERENT Team ID — it MUST be rejected and silently discarded (nothing
  installed, no indication). This is the proof of the same-Developer-ID
  authenticity guarantee (closes design open-question OQ5).

## Manual macOS 15 floor check (oldest-OS-only)

The test gate never runs on the floor: the Swift 6.3 toolchain is Xcode 26.4 or
newer, which does not install below macOS 26.2, so every CI runner and dev Mac is
newer than the oldest OS the app claims to support. No amount of green CI proves
the binary still launches on macOS 15.

**Owner:** the maintainer cutting the release.

**Trigger:** before shipping a release that touches the floor — a change to the
deployment target in `Package.swift`, to `LSMinimumSystemVersion`, to the actool
`--minimum-deployment-target` flags in the packaging scripts, or adoption of a
system API newer than the floor.

**Procedure:** package a signed build (`Scripts/sign-and-notarize.sh app`), copy
the resulting `Slovo.app` to a Mac running macOS 15 (Sequoia), and verify:

- **Launch:** the app starts with no dyld or missing-symbol error, and its glyph
  appears in the menu bar.
- **One full dictation round:** hold the push-to-talk key, speak, release — the
  cleaned text lands in the frontmost app.
- **Update check:** the dropdown's "Check for Updates…" row completes and reports
  a result instead of an error.

**Passing:** all three succeed on the macOS 15 machine. Any failure is a floor
violation — the deployment target claims an OS the binary cannot actually run on —
not a defect of that particular Mac, and it blocks the release until either the
cause is fixed or the floor is raised to an OS that does work.
