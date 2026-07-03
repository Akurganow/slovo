# Changelog

All notable changes to this project are documented here.

The format follows Keep a Changelog, and this project uses Semantic Versioning
once public releases begin.

## [0.3.0] - 2026-07-03

### Added

- Distributable notarized DMG. The packaging script signs with Developer ID,
  notarizes through `notarytool`, and builds a drag-to-Applications DMG.
  Developer ID signing and notarization are now configured — previously a known
  limitation.
- Application icon: the Glagolitic capital letter Slovo (Ⱄ) as a strictly
  monochrome pair that follows the system light and dark appearance.
- "Add Vocabulary…" menu item to add comma-separated terms that cleanup
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
