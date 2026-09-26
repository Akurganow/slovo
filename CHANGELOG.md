# Changelog

All notable changes to this project are documented here.

The format follows Keep a Changelog, and this project uses Semantic Versioning
once public releases begin.

## [0.32.1] - 2026-09-26

### Fixed

- Stop declaring an unused Speech Recognition permission (#107)

## [0.32.0] - 2026-09-19

### Added

- Refuse a press made while the previous dictation is processing (#81)

## [0.31.1] - 2026-09-19

### Fixed

- Refresh the release-tooling lockfile, drop dead test scaffolding, correct stale prose (#80)

## [0.31.0] - 2026-09-19

### Added

- One speech model per process, live recognition language, named failures in the log (#78)

## [0.30.2] - 2026-09-05

### Fixed

- Let the build and plugin stages fail, and analyze what SourceKit can read (#42)

## [0.30.1] - 2026-09-05

### Fixed

- Abort a superseded failure-glyph reset instead of clearing the newer glyph (#40)

## [0.30.0] - 2026-08-26

### Added

- Offer only the cleanup models the OpenRouter key can call (#34)

## [0.29.1] - 2026-08-18

### Fixed

- Never execute an instruction-shaped transcript (#29)

## [0.29.0] - 2026-08-14

### Added

- Gate fully silent holds instead of decoding hallucinations (#28)

## [0.28.1] - 2026-08-14

### Fixed

- Retry an empty biased tail decode without bias (#27)

## [0.28.0] - 2026-08-14

### Added

- Encrypt the personalization database at rest with SQLCipher (#26)

## [0.27.0] - 2026-08-14

### Added

- Rank the ASR bias head by observed vocabulary misses (#25)

## [0.26.0] - 2026-08-13

### Added

- Release the macOS 15 support landed in #24

## [0.25.0] - 2026-08-13

### Added

- Cleanup vocabulary correction and experimental ASR vocabulary bias v2 (#23)

## [0.24.2] - 2026-08-12

### Fixed

- Point the OpenRouter referer header at the real repository URL (#22)

## [0.24.1] - 2026-08-10

### Fixed

- Move the update row below both key hints (#20)

## [0.24.0] - 2026-08-10

### Added

- Add on-device grammar findings to the cleanup advisory (#19)

## [0.23.0] - 2026-08-07

### Added

- Configurable translate key (#15)

## [0.22.1] - 2026-08-06

### Fixed

- Update Sparkle to 2.9.5 (security) (#14)

## [0.22.0] - 2026-08-03

### Added

- Show Glagolitic Nash glyph while update awaits restart (#12)

## [0.21.0] - 2026-08-02

### Added

- Optional audio cues for push-to-talk dictation (#11)

## [0.20.0] - 2026-07-30

### Added

- Dev-build marker on the About version line

### Fixed

- Seed preferred status-item position so the icon lands visibly on crowded bars
- Either-side Option trigger, robust fn release edge, fn-conflict menu notice
- Per-side trigger set, drop Control, stop on the trigger's own key code
- Report Preparing Speech Model only when the model actually loads

## [0.19.0] - 2026-07-25

### Added

- Write dictated math expressions in conventional notation
- Add a detached full-benchmark launcher with inspectable state
- Add shared set of language-neutral formula exemplars

## [0.18.0] - 2026-07-25

### Added

- Rework both prompts around a bundled few-shot example catalog

## [0.17.0] - 2026-07-24

### Added

- Break the key-up latency span into attributable marks
- Confirm streamed segments during the hold, decode only the tail
- Shorten the failure-glyph flash to one second

## [0.16.0] - 2026-07-23

### Added

- Always-visible actionable update row with manual check

## [0.15.0] - 2026-07-23

### Added

- Semantic recording-glyph family — Cherv clean, Glagoli raw
- Remove-key button with funnel-routed availability refresh
- No-key cleanup affordances and menu restructure

### Fixed

- Present the keyboard language as the most likely dictation language
- Enforce the token-clean transcript domain at the source
- The cleanup pane observes availability instead of snapshotting
- Latch translate from a pre-held left Control at the start edge
- Intercept an empty transcript before cleanup and injection
- Dedicated add-key window replaces the settings-pane detour

## [0.14.2] - 2026-07-19

### Fixed

- Correct the About copy and set the wordmark in Glagolitic

## [0.14.1] - 2026-07-18

### Fixed

- Clear the update row's stale VoiceOver label outside ready

## [0.14.0] - 2026-07-18

### Added

- Add automatic updates via Sparkle

## [0.13.1] - 2026-07-18

### Fixed

- Place About as the first interactive menu item

## [0.13.0] - 2026-07-18

### Added

- Add About window with quick guide and version

## [0.12.0] - 2026-07-17

### Added

- Mark translate hold with the Pokoji recording glyph

## [0.11.0] - 2026-07-17

### Added

- Translate mode on push-to-talk + Control

## [0.10.0] - 2026-07-17

### Added

- Add menu-bar switch to mute system audio while dictating

### Fixed

- Render the menu-bar failure glyph red
- Run the publish job on macOS for the version stamp

## [0.9.0] - 2026-07-14

### Fixed

- For short dictations where live recognition has produced text but has not yet
  confirmed any prefix, Slovo now rejects an added terminal suffix only when the
  final decode is the exact normalized live result plus anomalous words
  timestamped strictly beyond the recorded audio. Every uncertain case keeps the
  final decode.

## [0.8.0] - 2026-07-13

### Changed

- On-device speech recognition now runs continuously while push-to-talk is held,
  so only the final audio tail remains to finish after key release before cleanup.

### Fixed

- The Add Vocabulary field now receives keyboard focus as soon as its window
  opens, allowing immediate typing without an extra click.

## [0.7.0] - 2026-07-12

### Changed

- GPT-5.6 Luna replaces GPT-5.4 nano as the default cleanup model. Existing
  selections of the retired GPT-5.4 nano catalog entry migrate to the new
  default; custom OpenRouter model ids remain unchanged.
- MiniMax M3 is now available as an additional curated cleanup model.
- The cleanup benchmark reference includes fresh 10-repetition measurements
  for GPT-5.6 Luna and MiniMax M3 over the 31-sample suite.

## [0.6.0] - 2026-07-11

### Added

- **Open at login** — a toggle in Settings → General starts Slovo automatically
  when you sign in (off by default), using the system login-item mechanism
  (`SMAppService`).
- Vocabulary editing in Settings → Vocabulary now has the native macOS ＋ / －
  controls below the list: select a term and click － to remove it, or click ＋
  to add terms. Swipe-to-delete and the Delete key still work.

## [0.5.0] - 2026-07-11

### Added

- The push-to-talk key is now configurable. Keep the default `fn` / Globe key
  or choose a right-hand modifier (⌘, ⌥, ⌃, ⇧) in **Settings → General**;
  a right-hand modifier still works normally on its own, and pressing another
  key mid-hold silently cancels the dictation so the real shortcut fires.
- A native **Settings** window with General, Cleanup, and Vocabulary tabs
  replaces the old modal dialogs — enter your OpenRouter key, pick the
  push-to-talk key and recognition language, choose the cleanup model and
  style, and add or remove vocabulary terms in one place.
- On-device cleanup hints: your active keyboard language and the system spell
  checker are passed to the cleanup model as advisory context to improve short
  or ambiguous phrases. Nothing but transcript text leaves the Mac, and the
  spell-check hints have a toggle in **Settings → Cleanup**.
- The recognition-language picker now offers every language WhisperKit
  supports, sourced directly from the library — a WhisperKit update that adds
  languages surfaces them automatically, with no hardcoded list to maintain.
  **Automatic** stays the default and handles mixed Russian + English best.

### Changed

- Configuration and key entry moved out of modal alerts into the Settings
  window; errors still surface only through the menu-bar icon.

## [0.4.0] - 2026-07-07

### Fixed

- Cleanup no longer adds words you did not dictate. Several cleanup models
  appended closing pleasantries such as "thank you" or "спасибо" that were never
  spoken; the cleanup instructions now explicitly forbid inventing content.
- Dictated text is reliably inserted instead of your previous clipboard contents.
  In slower apps (for example Codex and other Electron-based apps) the clipboard
  was restored before the paste landed, so the old clipboard was pasted; the
  restore now waits long enough (300 ms) for the paste to complete.
- Distribution packaging now staples the notarization ticket to `Slovo.app`
  before copying it into the DMG, then notarizes and staples the DMG. This avoids
  publishing a drag-installed app bundle that passes online Gatekeeper checks but
  is missing its own stapled ticket.

### Changed

- Switching the cleanup model takes effect immediately and no longer shows the
  "Preparing Speech Model" loading indicator or reloads the on-device speech
  model — only the cleanup step changes.
- First-run setup is guided from the menu-bar status and menu; the modal
  "Continue Setup" dialog was removed (it reappeared once for every missing
  permission and merely preceded the system prompt).

## [0.3.1] - 2026-07-03

### Fixed

- Recording no longer crashes after an audio device change. Changing the input
  or output device between dictations (for example unplugging headphones) left
  the reused audio engine with a stale hardware format, so the next capture
  raised an uncatchable exception. Each capture now builds a fresh engine, tracks
  `AVAudioEngineConfigurationChange`, and turns any residual format mismatch into
  a recoverable menu-bar status instead of aborting.

## [0.3.0] - 2026-07-03

### Added

- Distributable notarized DMG. The packaging script signs with Developer ID,
  notarizes through `notarytool`, and builds a drag-to-Applications DMG.
  Developer ID signing and notarization are now configured — previously a known
  limitation.
- Application icon: the Glagolitic capital letter Slovo (Ⱄ) as a strictly
  monochrome pair that follows the system light and dark appearance.
- "Add Vocabulary..." menu item to add comma-separated terms that cleanup
  preserves verbatim; new terms apply on the next dictation without a restart.

### Changed

- Menu-bar state glyphs are uppercase Glagolitic letters throughout.

### Fixed

- Saving the OpenRouter key no longer triggers a repeated Keychain password
  prompt. The key item is recreated so the running app owns it, instead of
  writing into an access list left by a differently signed build.

## [0.2.0] - 2026-07-03

### Changed

- Simplified transcript cleanup to OpenRouter-only routed model selection.
- Removed direct Anthropic/OpenAI cleanup providers and embedded local cleanup
  models.
- Updated the cleanup benchmark to compare OpenRouter model ids against the
  local pass-through baseline.
- Relicensed the project under the GNU General Public License v3.0.

## [0.0.1] - 2026-06-30

### Added

- Initial macOS menu-bar dictation app.
- Push-to-talk `fn` / Globe trigger with system-output mute and restore.
- Local microphone capture and WhisperKit-backed transcription path.
- Optional transcript cleanup through Anthropic or OpenAI.
- Provider-specific cleanup model selection from menu controls.
- macOS Keychain storage for Anthropic and OpenAI API keys.
- Clipboard paste injection with secure-input checks and clipboard restore.
- Local SQLite personalization schema and vocabulary path.
- AppKit status menu, setup prompts, and signed `.app` packaging script.
- Strict Swift build settings, Swift Testing coverage, SwiftLint, and static
  guard checks.

### Known Limitations

- Developer ID signing and notarization are not configured in the repository.
- Real TCC permission persistence and ASR bias effectiveness remain L4 manual
  checks on the user's Mac.
- Cleanup latency depends on the selected cloud provider and model.
