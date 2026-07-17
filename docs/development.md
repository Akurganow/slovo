# Development

## Requirements

- Apple Silicon Mac.
- macOS 26 or newer.
- Xcode with Swift 6.3 toolchain.
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

The gate runs build, tests, and strict lint as separate stages. This keeps one
failure from hiding another.

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

Compare cleanup candidates with the non-product benchmark executable:

```sh
swift run --disable-automatic-resolution slovo-cleanup-benchmark \
  --env-file .env \
  --providers openrouter:openai/gpt-5.6-luna,openrouter:anthropic/claude-haiku-4.5,openrouter:google/gemini-3.1-flash-lite,openrouter:qwen/qwen3.6-flash,openrouter:deepseek/deepseek-v4-flash,openrouter:mistralai/mistral-small-2603,openrouter:minimax/minimax-m3,passthrough \
  --repetitions 10 \
  --failure-breakdown \
  --category-breakdown
```

The benchmark reads API keys from environment variables or the optional env file,
not from Keychain. It prints aggregate latency, quality counts, and optional
failure-code counts only; transcripts and cleaned output stay out of the report.
OpenRouter candidates require `OPENROUTER_API_KEY`; `passthrough` is the local
baseline and does not read network credentials.

See [cleanup-benchmark.md](references/cleanup-benchmark.md) for sample-file
format and benchmark reporting notes.

## Packaging

Packaging runs in two phases (`app`, then `dmg`); use a stable signing identity:

```sh
SIGNING_IDENTITY="Developer ID Application: Alexander Kurganov (ZN8H5SF4R7)" Scripts/sign-and-notarize.sh app
```

The script refuses ad-hoc signing unless `ALLOW_AD_HOC_SIGNING=1` is set. See
[release-checklist.md](release-checklist.md) for the full flow; stapling the
notarization ticket is the only manual step. Published releases are fully
automated on CI — see [release-ci.md](release-ci.md); this section covers local
verification builds only.

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
- **Each right modifier (⌘, ⌥, ⌃, ⇧):** select it in Settings → General, then hold it
  alone to dictate; the modifier still works normally system-wide (it is not
  suppressed).
- **Interrupt:** hold the selected right modifier and press another key mid-hold
  (e.g. Right ⌘ then C) — dictation is cancelled silently (nothing inserted, no
  error, menu-bar glyph returns to idle) and the real shortcut still fires.
- **Live change:** switch the key in Settings → General while idle — the new key works
  on the next dictation with no "Preparing Speech Model" pulse.
- **Translate latch:** hold the push-to-talk key and press or hold Control at any
  point before releasing — the dictation is translated into the configured target
  (menu bar / Settings → Cleanup), and the menu-bar recording glyph switches live
  to Pokoji `Ⱂ` while Control is latched; a hold without Control is not translated
  and keeps the plain recording glyph.
