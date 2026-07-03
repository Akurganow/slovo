# Architecture

Slovo is a native Swift menu-bar app with a small composition root and testable
core seams.

## Pipeline

The dictation flow is:

```text
fn down -> mute output -> capture microphone
fn up   -> stop capture -> restore output -> transcribe -> clean -> inject
```

Raw audio stays on the Mac and is transcribed on-device through WhisperKit
(Whisper large-v3 turbo). Cleanup is always attempted through OpenRouter and
sends only transcript text for the selected routed model id.

## Core Components

- `HotkeyMonitor` observes the global `fn` / Globe key.
- `SystemAudioController` mutes and restores system output during recording.
- `AudioRecorder` captures microphone audio and converts it to 16 kHz mono float
  samples.
- `WhisperKitTranscriber` turns audio into text through `WhisperKitEngine`
  (Whisper large-v3 turbo), keeping the model resident between dictations.
- `Cleaner` rewrites the transcript into final prose when OpenRouter cleanup
  succeeds.
- `Injector` inserts the final text into the focused field.
- `PersonalizationSource` supplies local vocabulary hints.
- `Orchestrator` serializes the pipeline and owns the runtime state transitions.

The app target owns OS-specific adapters and production composition. `SlovoCore`
owns the seams, value types, state machine, storage, cleanup, transcription, and
injection behavior.

## Cleanup

Cleanup has one runtime provider:

- OpenRouter Chat Completions API.

The app stores one OpenRouter key in Keychain and exposes model selection as
curated OpenRouter model ids and a custom id entry. Selecting a model changes
only the model id. The key is read lazily when cleanup runs.

Cleanup is sad-to-fail. If OpenRouter is missing, unavailable, misconfigured,
refuses the request, rate-limits, or returns an unusable response, Slovo inserts
the direct transcript and briefly shows the `Ⱁ` error glyph instead of
cancelling the dictation.

## Storage

Slovo uses SQLite through GRDB for local personalization data:

- `vocabulary` stores spelling anchors and term weights.
- `corrections` is reserved for future correction memory.
- `profile` stores small local context facts.

The repository tracks only schema and migrations. Local databases and seed files
are never committed.

## Menu-Bar App

The app is packaged as an `LSUIElement` menu-bar app. It has no Dock icon and uses
an `NSStatusItem` for status, cleanup model selection, OpenRouter key entry,
vocabulary quick-add, first-run setup actions, and quit.

## Build Boundaries

SwiftPM is the source of truth. All targets build with warnings as errors, strict
concurrency checking, and actor data-race checks. SwiftLint is pinned through a
SwiftPM plugin and is part of the release gate.
