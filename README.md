# Slovo

Slovo is a private, on-device push-to-talk dictation app for macOS. Hold your
push-to-talk key — the `fn` / Globe key by default — speak, release, and Slovo
inserts the cleaned-up text into the focused field.

The privacy boundary is deliberately narrow: raw audio stays on the Mac.
Cleanup is always attempted through OpenRouter; only the already-transcribed
text is sent for model-routed text cleanup.

[![Swift CI](https://github.com/Akurganow/slovo/actions/workflows/swift.yml/badge.svg)](https://github.com/Akurganow/slovo/actions/workflows/swift.yml)
[![Release](https://img.shields.io/github/v/release/Akurganow/slovo)](https://github.com/Akurganow/slovo/releases/latest)
[![License: GPL v3](https://img.shields.io/github/license/Akurganow/slovo)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-blue)
![Swift](https://img.shields.io/badge/swift-6.3-orange)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-support-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/akurganow)

This is an early release: the app is usable and ships as a Developer ID
signed, notarized DMG, but recognition and cleanup quality are still being
tuned.

## Features

- Push-to-talk dictation from a configurable key — the `fn` / Globe key by
  default, or a right-hand modifier (⌘, ⌥, ⌃, ⇧), chosen in Settings.
- Local speech capture and on-device transcription through WhisperKit
  (Whisper large-v3 turbo), including mixed Russian + English in one
  utterance.
- Text cleanup through OpenRouter, with curated routed models and custom
  OpenRouter model ids.
- On-device cleanup hints: your active keyboard language and the system spell
  checker nudge the model toward the right words, without ever leaving the Mac.
- OpenRouter API key stored in macOS Keychain and read only when cleanup
  runs.
- Clipboard-based text insertion with secure-input checks and clipboard
  restore.
- Local SQLite personalization store for vocabulary hints — add and remove
  terms in **Settings → Vocabulary**, or use the menu-bar **Add Vocabulary...**
  quick action — to protect your own terms during cleanup.
- Menu-bar status glyphs (Glagolitic letters) for idle, recording, and
  processing states, plus a monochrome app icon that follows the system
  theme.
- A native **Settings** window (General, Cleanup, Vocabulary) for the
  push-to-talk key, recognition language, launch at login, cleanup model and
  style, API key, and vocabulary.
- Strict Swift build, test, concurrency, lint, and static guard checks.

## Requirements

- Apple Silicon Mac.
- macOS 26 or newer.
- Microphone and Accessibility permissions. Input Monitoring may be
  requested only as a targeted hotkey recovery step if the event tap
  cannot start.
- An OpenRouter API key for cleanup.

On first use, WhisperKit downloads the speech model once over the network;
after that, transcription runs fully on-device.

## Install

1. Download `Slovo.dmg` from the
   [latest release](https://github.com/Akurganow/slovo/releases/latest).
2. Open the DMG and drag **Slovo** into **Applications**.
3. Launch Slovo from Applications. It lives in the menu bar — there is no
   Dock icon.
4. Grant **Microphone** and **Accessibility** when prompted. Accessibility
   is required for the global `fn` / Globe hotkey.
5. Open the menu-bar item, choose **Update OpenRouter Key** to enable
   cleanup, and optionally **Add Vocabulary...** to protect your own terms.

## Usage

1. Hold `fn` / Globe. Microphone capture and on-device transcription both
   start immediately.
2. Speak. While the key is held, transcription keeps up with your speech,
   so the transcript is already ready (or nearly ready) the moment you
   release.
3. Release `fn` / Globe. Cleanup runs immediately through OpenRouter, then
   the cleaned text is inserted into the focused field.
4. If you held the key but only silence was captured, the menu-bar icon
   briefly shows the Glagolitic letter `Ⱀ` and nothing is inserted — this is
   not an error and needs no action.
5. If cleanup itself fails (unavailable, refused, misconfigured, or a
   provider/network error — never because a setting disabled cleanup), the
   raw transcript is inserted instead and the menu-bar icon briefly shows
   the error glyph `Ⱁ`.

Errors surface only through the menu-bar icon — never an alert, dialog, or
focus-stealing notification, since Slovo types into whichever app you're
already using.

## Privacy Model

Slovo has two different data paths:

- Audio path: microphone audio is captured and transcribed locally through
  WhisperKit. Raw audio never leaves the machine. The Whisper model itself
  is a third-party asset: WhisperKit downloads it once (from Hugging Face)
  on first use and caches it under Application Support; transcription then
  runs fully on-device with no per-dictation network calls.
- Cleanup path: transcript text is sent to OpenRouter when cleanup is
  available. OpenRouter routes the request to the selected model id.

Secrets are not stored in the repository. The OpenRouter API key is stored
as a macOS Keychain item. Local personalization databases, seed files,
dotenv files, signing keys, and credential bundles are ignored by Git. See
[docs/privacy.md](docs/privacy.md) for the full data-path table.

## Configuration

Runtime settings are stored in `UserDefaults`. The OpenRouter API key is
stored in Keychain:

- OpenRouter service/account: `slovo` / `openrouter-api-key`
- ASR backend/model: `whisperkit` / `large-v3-v20240930_turbo_632MB`

The app also accepts an environment variable as a development-only
override:

- `OPENROUTER_API_KEY`

## Build And Test

Building from source requires Xcode with the Swift 6.3 toolchain — see
[CONTRIBUTING.md](CONTRIBUTING.md) for the full contributor setup. Install
dependencies through Swift Package Manager using the checked-in
`Package.resolved` file:

```sh
swift build --disable-automatic-resolution
swift test --disable-automatic-resolution
```

Run the full local gate before shipping changes:

```sh
Scripts/diagnose.sh
```

`Scripts/diagnose.sh` runs build, tests, and strict lint as independent
stages so one failure does not hide another.

Compare cleanup latency and quality with the non-product benchmark:

```sh
swift run --disable-automatic-resolution slovo-cleanup-benchmark \
  --env-file .env \
  --providers openrouter:openai/gpt-5.6-luna,openrouter:anthropic/claude-haiku-4.5,openrouter:google/gemini-3.1-flash-lite,openrouter:qwen/qwen3.6-flash,openrouter:deepseek/deepseek-v4-flash,openrouter:mistralai/mistral-small-2603,openrouter:minimax/minimax-m3,passthrough \
  --repetitions 10 \
  --failure-breakdown \
  --category-breakdown
```

See [docs/references/cleanup-benchmark.md](docs/references/cleanup-benchmark.md)
for the latest latency/quality snapshot and the curated model reference
table.

## Run Locally

For a fast signed development launch, build and open a staged menu-bar
bundle:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  Scripts/build_and_run.sh --verify
```

The script rebuilds the `slovo` product, stages `.build/dev-run/Slovo.app`,
signs it with a stable local code-signing identity and the app
entitlements, opens it, and verifies that the `slovo` process is running.
Stable signing is required for macOS TCC permission persistence; pass the
identity explicitly so a different certificate cannot be selected implicitly.

Published releases are fully automated: a push to `main` runs one pipeline that
decides from the conventional commits whether a release is due, computes the next
version, and runs the full build/sign/notarize/staple chain on GitHub-hosted macOS
runners, then tags `v<version>` and publishes the stapled DMG to a GitHub Release.
Nobody runs a release command, edits a version, or pushes a tag by hand. See
[docs/release-ci.md](docs/release-ci.md) for the CI flow and triggers. The local
flow below is only for verifying a build before it is merged.

Packaging runs in two automated phases: build/sign/notarize the app, then
package the stapled app into a DMG. Stapling the notarization ticket is the
only manual step locally and must run on a Mac that can reach Apple's
notarization service:

```sh
# 1. build, sign, and notarize the app
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE="slovo-notary" Scripts/sign-and-notarize.sh app
# 2. staple the app (manual, on a networked Mac)
xcrun stapler staple .build/dist/Slovo.app
# 3. package the stapled app into a signed, notarized DMG
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE="slovo-notary" Scripts/sign-and-notarize.sh dmg
# 4. staple the DMG (manual, on a networked Mac)
xcrun stapler staple .build/dist/Slovo.dmg
```

`NOTARY_PROFILE` (a `notarytool` keychain profile) enables notarization;
omit it to stop after signing. Stapling is a separate manual step because
it contacts Apple's CloudKit endpoint and can fail behind a TLS-inspecting
proxy even when notarization succeeds; run it on a network that does not
break Apple certificate pinning. See
[docs/release-checklist.md](docs/release-checklist.md) for verification
steps.

The signing script intentionally rejects ad-hoc signing by default because
macOS privacy grants and Keychain trust are tied to a stable app identity.
For local experiments only, ad-hoc signing can be forced:

```sh
ALLOW_AD_HOC_SIGNING=1 SIGNING_IDENTITY=- Scripts/sign-and-notarize.sh app
```

After first launch, grant the requested setup permissions in System
Settings, then use the Slovo menu to retry setup and enter the OpenRouter
key.

## Documentation

- [Architecture](docs/architecture.md)
- [Privacy and security](docs/privacy.md)
- [Development](docs/development.md)
- [Development reference library](docs/references/README.md)
- [Release checklist](docs/release-checklist.md)
- [Release CI/CD](docs/release-ci.md)
- [Cleanup benchmark reference](docs/references/cleanup-benchmark.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The short version: keep changes
small, run `Scripts/diagnose.sh`, do not commit secrets or local
personalization data, and document behavior changes in English.

## Support

Slovo is free, open source, and has no telemetry or paid tier. If it's useful
to you, [support development on Ko-fi](https://ko-fi.com/akurganow) — it goes
toward the Apple Developer Program membership and test hardware that keep
releases signed and notarized.

## Security

See [SECURITY.md](SECURITY.md). Please do not include API keys,
transcripts, personal vocabulary, local databases, or private work
terminology in public issues.

## License

GNU General Public License v3.0. See [LICENSE](LICENSE).

Slovo is copyleft: any distributed work based on this source must itself
be released under the GPLv3. The bundled dependencies (GRDB.swift,
argmax-oss-swift / WhisperKit) are MIT-licensed and compatible with this
license.
