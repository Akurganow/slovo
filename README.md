# Slovo

Slovo is a private, on-device push-to-talk dictation app for macOS. Hold your
push-to-talk key — the `fn` / Globe key by default — speak, release, and Slovo
inserts the cleaned-up text into the focused field.

The privacy boundary is deliberately narrow: raw audio stays on the Mac, and
speech is recognized on the Mac. While cleanup is on (the default), each
dictation sends its transcript to OpenRouter for model-routed text cleanup,
together with your vocabulary and on-device language hints. With cleanup off, no
part of a dictation leaves the Mac. [docs/privacy.md](docs/privacy.md) lists
everything Slovo sends and when.

[![Swift CI](https://github.com/Akurganow/slovo/actions/workflows/swift.yml/badge.svg)](https://github.com/Akurganow/slovo/actions/workflows/swift.yml)
[![Release](https://img.shields.io/github/v/release/Akurganow/slovo)](https://github.com/Akurganow/slovo/releases/latest)
[![License: GPL v3](https://img.shields.io/github/license/Akurganow/slovo)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-blue)
![Swift](https://img.shields.io/badge/swift-6.3-orange)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-support-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/akurganow)

This is an early release: the app is usable and ships as a Developer ID
signed, notarized DMG, but recognition and cleanup quality are still being
tuned.

## Features

- Push-to-talk dictation from a configurable key — the `fn` / Globe key by
  default, or one side of ⌘, ⌥, ⇧ — or ⌃, where either Control key counts —
  chosen in Settings.
- Local speech capture and on-device transcription through WhisperKit
  (Whisper large-v3 turbo; part of the Argmax OSS SDK, formerly the
  standalone WhisperKit package), including several languages mixed within a
  single utterance.
- Text cleanup through OpenRouter, with curated routed models and custom
  OpenRouter model ids. Pick a model under **Model** in **Settings → Cleanup**
  or from **Cleanup Model: …** in the menu bar. A custom id goes in the field
  under the list and takes effect with **Use**. Once Slovo knows which models
  your key can call, the curated models in both places are limited to those.
- A cleanup switch, on by default: **Clean Up Dictation** in the menu bar and
  **Clean up dictation** in **Settings → Cleanup**. Turn it off for the explicit
  raw-transcript mode: the dictation makes no network request, and the raw final
  transcript lands in the focused field once at key-up, near-instantly.
  Translation is unavailable while cleanup is off. With no OpenRouter key saved,
  cleanup is off as well: the menu shows **Add OpenRouter Key…** in place of the
  switch, and the Settings switch is off and cannot be turned on.
- Optional per-dictation translation from a **Translate key** of its own — ⌃ by
  default, drawn from the same pool as the push-to-talk key and never the same
  key. It is an *additional* key by default: hold it together with the
  push-to-talk key and that dictation is translated into your target language as
  part of the same cleanup step. Turn **Use as additional key** off and it
  becomes a second push-to-talk key that always translates. Either way a plain
  hold is unchanged.
- Optional muting of system audio while dictating. A **Mute Audio While
  Dictating** switch (on by default) sits in Settings → General and in the
  menu-bar dropdown. It silences playback while speech is delivered to
  recognition and restores it afterward. On an output device where macOS can set
  neither the mute nor the volume, both switches are disabled, and Settings
  explains why.
- A **Microphone** choice in the menu-bar dropdown and in Settings → General picks
  the input dictation records from: **System Default** (the default) or one
  specific device. A chosen device that is not connected falls back to the system
  default, and Settings says so.
- Multi-channel audio interfaces are recorded from their main stereo pair, the two
  inputs macOS uses for stereo. A loopback pair on other channels stays out of
  dictation.
- **Sound Cues** for recording readiness, key-up, and failures (on by default),
  switchable in Settings → General or beside Mute in the menu-bar dropdown. Cues
  never hold up dictation: the microphone opens without waiting for a cue, and
  releasing the key stops recording immediately. Nothing is cut from the recording
  for a cue, so you can speak at the press. In a quiet room, a press with no
  speech can insert a stray phrase as text. Turning Sound Cues off
  avoids it. End marks the end of recording rather than a successful
  transcription: it plays at key-up, together with the glyph change, and never
  delays cleanup. Error accompanies the red failure glyph. Intentional
  cancellation stays silent. Cue loudness follows the macOS system alert volume,
  and Slovo has no separate volume control.
- Cleanup hints: your active keyboard language and the system spell and grammar
  checker nudge the model toward the right words. Slovo gathers them on your Mac,
  then sends them to OpenRouter with the transcript as advisory context. Turn
  off **Use system spell and grammar hints** in **Settings → Cleanup** (on by
  default) to stop the spell and grammar hints. The keyboard language is sent
  whenever cleanup runs and macOS reports one. Grammar hints are English-only,
  as macOS ships grammar rules for English alone.
- OpenRouter API key stored in macOS Keychain. Add it through the menu-bar
  **Add OpenRouter Key…** window or **Settings → Cleanup**. A **Remove Key…**
  button in **Settings → Cleanup** deletes it, and cleanup then turns off until
  you add a key again. When Slovo reads the key, and when it makes the key-scope
  request, is in [docs/privacy.md](docs/privacy.md).
- Clipboard-based text insertion with secure-input checks and clipboard
  restore.
- Local SQLite personalization store for vocabulary hints, encrypted at rest
  with SQLCipher — add and remove terms in **Settings → Vocabulary**, or use the
  menu-bar **Add Vocabulary…** quick action — to protect your own terms during
  cleanup.
- Menu-bar status glyphs (Glagolitic letters) for idle, recording, and
  processing states — resting idle shows `Ⱄ` normally, swapping to `Ⱀ`
  when a downloaded update awaits restart; the recording glyph names the mode:
  `Ⱍ` clean, `Ⰳ` raw, `Ⱂ` translate — plus a monochrome app icon that follows
  the system theme.
- A native **Settings** window, opened from **Settings…** in the menu bar. It
  opens on the pane you last viewed, never on **About**, and on **General**
  after a launch. **General** holds the push-to-talk and translate keys, the
  recognition language, the microphone, muting, sound cues, **Vocabulary bias
  (experimental)**, **Open at login** and **Automatically install updates**.
  **Cleanup** holds the cleanup switch, the model, the **Writing style**
  (**Formal**, **Casual** or **Very casual**; Casual by default), the
  translation target, the API key and the spell and grammar hints switch.
  **Vocabulary** holds your terms. **About** is described below.
- **Vocabulary bias (experimental)**, off by default, also passes your
  highest-weighted vocabulary terms to the on-device speech recognizer. Your
  vocabulary reaches cleanup whether it is on or off.
- An **About** pane in Settings with a built-in quick guide (dictate,
  cleanup, translate, vocabulary) and the running version. **About Slovo**
  in the menu bar opens it.
- Silent automatic updates with an always-visible menu-bar update row:
  **Check for Updates…** runs a manual silent check, **Checking…** shows while
  any check runs, **Downloading v…** shows while an update downloads, and a
  downloaded update switches the status bar glyph to `Ⱀ` and offers **Update
  ready — v…** / **Restart**. The **Automatically install updates** switch
  (Settings → General, on by default) turns scheduled checking off.
- Strict Swift build, test, concurrency, lint, and static guard checks.

## Requirements

- Apple Silicon Mac.
- macOS 15 (Sequoia) or newer.
- Microphone and Accessibility permissions. Input Monitoring may be
  requested only as a targeted hotkey recovery step if the event tap
  cannot start.
- An OpenRouter API key for cleanup (optional — without one, Slovo still
  dictates, inserting the raw transcript).

On first use, WhisperKit downloads the speech model from Hugging Face. Each
time Slovo loads the model, which is at launch, WhisperKit first checks the
cached copy with Hugging Face. Transcription itself runs on the Mac.
[docs/privacy.md](docs/privacy.md), "Speech Model", has the details.

## Install

1. Download `Slovo.dmg` from the
   [latest release](https://github.com/Akurganow/slovo/releases/latest).
2. Open the DMG and drag **Slovo** into **Applications**.
3. Launch Slovo from Applications. It lives in the menu bar — there is no
   Dock icon.
4. Grant **Microphone** and **Accessibility** when prompted. Accessibility
   is required for the global `fn` / Globe hotkey. Until both are granted, the
   menu shows **Slovo Setup Required**, a **Request Microphone Access** or
   **Request Accessibility Access** row for each missing permission, and
   **Retry Setup**. If the hotkey cannot start, it shows **Slovo Hotkey Setup
   Required** with **Request Input Monitoring Access** and **Retry Setup**.
5. Cleanup is optional: open the menu-bar item, choose **Add OpenRouter
   Key…**, and save your OpenRouter API key in the small key window to enable
   it (the key can be managed later in **Settings → Cleanup**). Optionally use
   the menu-bar **Add Vocabulary…** action to protect your own terms.

## Usage

1. Hold `fn` / Globe. Microphone capture and on-device transcription start
   immediately. With **Sound Cues** on, Start plays once both are ready. You need
   not wait for it. If mute-while-dictating is on, playback is muted once Start
   is done.
2. Speak. While the key is held, transcription keeps up with your speech,
   so the transcript is already ready (or nearly ready) the moment you
   release.
3. Release `fn` / Globe. Cleanup runs immediately through OpenRouter, then
   the cleaned text is inserted into the focused field. With **Clean Up
   Dictation** off (or no key saved), the raw transcript is inserted instead,
   near-instantly and with no network request.
4. If you held the key but only silence was captured, nothing is inserted and
   the menu-bar icon briefly shows the red failure glyph `Ⱁ`. With Sound Cues
   on you hear End at key-up, since recording did end, and then Error — no
   alert dialog or persistent notice.
5. If cleanup itself fails (unavailable, refused, misconfigured, or a
   provider/network error), the raw transcript is inserted instead and the
   menu-bar icon briefly shows the error glyph `Ⱁ`. Cleanup turned off by
   choice is not a failure — raw mode inserts silently, with no error glyph.

To translate a dictation, use the **Translate key** — ⌃ out of the box, and
any other key from the same pool in **Settings → General**. By default it is
an additional key: press it at any moment while the push-to-talk key is down,
and that dictation is cleaned and translated into your target language in the
same single step, then inserted. Slovo sees ⌃ and `fn` in every keystroke, so
they count even if you were already holding one; a sided ⌘, ⌥ or ⇧ is noticed
only when that key itself moves, so it has to go down during the hold. A plain
hold (translate key untouched) is unchanged. Turn **Use as additional key**
off and the translate key stands alone: hold it by itself to dictate, and that
dictation is always translated, while the push-to-talk key keeps working as
plain dictation.
While a dictation is set to translate, the menu-bar recording glyph is the
Glagolitic letter Pokoji `Ⱂ` instead of the clean-mode recording glyph `Ⱍ` —
it switches the moment an additional translate key joins the hold, and shows
from the start of a standalone translate hold, so the mode is visible at a
glance. Translation requires cleanup: while **Clean Up Dictation** is off, the
translate key adds no translation and the recording glyph stays the raw-mode
`Ⰳ`.
Choose the target — the **Recognition language** list without **Auto** — from the
menu bar (**Translate to: …**) or **Settings → Cleanup**. If cleanup fails, the
raw untranslated transcript is inserted with the same `Ⱁ` notice — translation
adds no new error surface.

Failures surface through the menu-bar icon and, while **Sound Cues** is on, the
Error cue — never a dialog or focus-stealing notification, since Slovo types
into whichever app you're already using. Intentional cancellation is silent.
Open the menu for the reason: after most failures its first row names it, such
as **Secure Field Active** when Slovo refused to paste because secure input was
on, and it stays until your next dictation. **Inserted As Spoken**, after a
cleanup fallback, clears after about a second, and a hold with no speech shows
only the glyph. With nothing to report, that row reads the hold hint, for example “Hold fn to talk”. Under it, a row shows how to
translate: **Add ⌃ to translate** while the translate key is additional,
**Hold ⌃ to translate** while it stands alone (with your own keys in place of
⌃). With fn as the push-to-talk key or the translate key, and the Globe key also
assigned a macOS action, the menu adds a row between those two. It asks you to
set “Press 🌐 key to” to “Do Nothing” in System Settings ▸ Keyboard.

### When sound cues stop playing

If Start, End and Error are all silent while dictation still works, read the cue
log. With **Sound Cues** off there are no `cue.` lines, by design. If
`cue.completed` lines appear while you hear nothing, macOS reported the cue
finished. Check the alert volume and the output device. The recovery below does
not apply then.

Slovo writes each cue to the log as plain text. Run this in Terminal:

```sh
/usr/bin/log show --last 1h --style compact --predicate 'subsystem == "com.slovo.app" AND eventMessage BEGINSWITH "cue."'
```

On macOS 27.0, `/usr/bin/log help show` lists the options. It also says output
holds default-level messages only, so the info-level `cue.error reason=` line
does not appear.

What Slovo observed: a healthy cue shows `cue.requested`, then `cue.completed`
with its time in `ms`. A `cue.deadlineElapsed` line press after press means macOS
did not report the cue finished. A `cue.late` line for the same cue carries in
`ms` how long macOS took. No order is promised between a cue's `cue.late` and its
`cue.deadlineElapsed`. Lines of different dictations may interleave, so read them
per cue name. A `cue.failed` line means a cue sound did not load. The recovery
below does not apply to it.

Running `sudo killall systemsoundserverd` in Terminal with an administrator
account made cue sounds play again. It was checked on macOS 27.0 and macOS 26,
and not on other versions.

## Privacy Model

Slovo has two different data paths:

- Audio path: microphone audio is captured and transcribed on the Mac through
  WhisperKit. Raw audio never leaves the machine. The Whisper model is a
  third-party asset: WhisperKit downloads it from Hugging Face on first use and
  caches it under Application Support. Each time Slovo loads the model, which is
  at launch, WhisperKit first checks the cached copy with Hugging Face; the
  check carries no dictated content ([docs/privacy.md](docs/privacy.md), "Speech
  Model"). Transcription itself makes no network call.
- Cleanup path: while cleanup is on, each dictation sends OpenRouter its
  transcript, every vocabulary term with its expansion, your keyboard language,
  the chosen writing style and, while their switch is on, the spell and grammar
  findings. OpenRouter routes the request to the selected model id. Translation
  adds only the target-language name. A separate key-scope request carries your
  API key and no dictated content. With cleanup off (or no key saved) a
  dictation sends nothing, and the raw final transcript is inserted once at
  key-up.

[docs/privacy.md](docs/privacy.md) lists every request Slovo makes, what each
carries, and when it is sent.

In both modes the final text is inserted with a clipboard-based paste: Slovo
snapshots the clipboard, writes the text with conceal markers that ask
clipboard managers not to record it, pastes, and restores the previous
clipboard contents afterward.

Secrets are not stored in the repository. The OpenRouter API key is stored
as a macOS Keychain item. The personalization database is encrypted at rest
with SQLCipher, under a key derived from this Mac's hardware identifier and
stored nowhere, so a copy of it that leaves the Mac is unreadable without that
Mac's hardware identifier; the flip side is that it opens only on the Mac that
created it, and once an encrypting build has opened it, older Slovo builds can
no longer read it. Local personalization databases, seed files, dotenv files,
signing keys, and credential bundles are ignored by Git. See
[docs/privacy.md](docs/privacy.md) for what the encryption does and does not
protect against.

## Configuration

Runtime settings are stored in `UserDefaults`. The OpenRouter API key is
stored in Keychain:

- OpenRouter service/account: `slovo` / `openrouter-api-key`
- ASR backend/model: `whisperkit` / `large-v3-v20240930_turbo_632MB`

## Build And Test

Building from source requires Xcode with the Swift 6.3 toolchain — see
[CONTRIBUTING.md](CONTRIBUTING.md) for the full contributor setup. Install
dependencies through Swift Package Manager using the checked-in
`Package.resolved` file:

```sh
swift build --disable-automatic-resolution
swift test --disable-automatic-resolution
```

Run the full gate locally when you want it before pushing:

```sh
Scripts/diagnose.sh
```

What it runs, and how CI uses it, is in [docs/development.md](docs/development.md),
"Full Gate".

Compare cleanup latency and quality with the non-product benchmark:

```sh
swift run --disable-automatic-resolution slovo-cleanup-benchmark \
  --env-file .env \
  --providers catalog,passthrough \
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

Published releases are automated from `main`: nobody runs a release command,
edits a version, or pushes a tag by hand. See [docs/release-ci.md](docs/release-ci.md).
To package and notarize a build locally before merge, follow
[docs/release-checklist.md](docs/release-checklist.md), "Verify packaging before
merge (optional, local)".

After first launch, grant the requested setup permissions in System
Settings, then choose **Retry Setup** in the Slovo menu and add the OpenRouter
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
small, see the Swift check green on your pull request, do not commit secrets
or local personalization data, and document behavior changes in English.

## What Slovo Is Not

Slovo is deliberately small: hold a key, speak, release, get clean text.
Everything it does serves that single loop — dictate, clean up, optionally
translate, insert. To stay simple and unobtrusive, Slovo intentionally does
not implement:

- **No history.** Slovo keeps no transcript or cleaned text after the text is
  inserted — no transcript log to browse, search, or leak. When cleanup corrects
  one of your vocabulary terms, Slovo records which term and when, encrypted on
  your Mac and never sent. Records older than 90 days are ignored and deleted
  the next time Slovo records one ([docs/privacy.md](docs/privacy.md)).
- **No main window.** No overlay, no visible live transcript — only the
  menu-bar icon and the on-demand Settings and Add Vocabulary panels.
- **No features beyond the loop.** No meeting recording or file
  transcription, no voice commands or computer control, no snippets,
  modes, or personas.

This is today's deliberate scope, not a forever promise — but a feature
request that adds a new step to that loop will most likely be declined.

If you want a more capable or professional tool, these are excellent and
serve different needs:

- [Wispr Flow](https://wisprflow.ai) — polished, cross-platform AI
  dictation for everyday professional writing.
- [superwhisper](https://superwhisper.com) — deeply customizable Mac
  dictation with local or cloud models.
- [Spokenly](https://spokenly.app) — cross-platform dictation with local
  Whisper models, BYOK cloud providers, and AI text processing.
- [Talon](https://talonvoice.com) — full hands-free computer control,
  built for accessibility and voice coding.

And if you like Slovo's open-source, on-device approach but want more
features, have a look at [VoiceInk](https://tryvoiceink.com) (GPLv3,
built on whisper.cpp).

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

Copyright (C) 2026 Alexander Kurganov.

GNU General Public License v3.0. See [LICENSE](LICENSE).

Slovo is copyleft: any distributed work based on this source must itself
be released under the GPLv3.

The shipped app bundle redistributes several third-party components, all
under permissive licenses compatible with the GPLv3: WhisperKit
(argmax-oss-swift, MIT — with an Apache-2.0 portion, swift-transformers),
GRDB.swift (MIT, taken from Zetetic's SQLCipher-enabled distribution),
SQLCipher Community Edition (BSD-3-Clause), Settings (MIT), Sparkle (MIT,
with four external notices for bsdiff, sais-lite, ed25519, and
SUSignatureVerifier), and the modified AbdrTar Bank Elhaz “Lower & Soft”
sound cues (CC0 1.0). Applicable copyright and permission notices, plus the
audio sources and transformation recipe, are in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md), which also ships inside the
app (Settings ▸ About ▸ Acknowledgements).

`swift-argument-parser` (Apache-2.0) is resolved by the package graph but
not linked into the shipped executable, and SwiftLint is a build-time lint
tool only — neither is redistributed.
