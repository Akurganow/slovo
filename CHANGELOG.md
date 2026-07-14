# Changelog

All notable changes to this project are documented here.

The format follows Keep a Changelog, and this project uses Semantic Versioning
once public releases begin.

## [Unreleased]

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
