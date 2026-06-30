# Architecture

Slovo is a native Swift menu-bar app with a small composition root and testable
core seams.

## Pipeline

The dictation flow is:

```text
fn down -> mute output -> capture microphone
fn up   -> stop capture -> restore output -> transcribe -> clean -> inject
```

Raw audio stays on the Mac. The optional cloud step receives transcript text only.

## Core Components

- `HotkeyMonitor` observes the global `fn` / Globe key.
- `SystemAudioController` mutes and restores system output during recording.
- `AudioRecorder` captures microphone audio and converts it to 16 kHz mono float
  samples.
- `Transcriber` turns audio into text.
- `Cleaner` optionally rewrites the transcript into final prose.
- `Injector` inserts the final text into the focused field.
- `PersonalizationSource` supplies local vocabulary hints.
- `Orchestrator` serializes the pipeline and owns the runtime state transitions.

The app target owns OS-specific adapters and production composition. `SlovoCore`
owns the seams, value types, state machine, storage, cleanup, transcription, and
injection behavior.

## Cleanup Providers

Cleanup is provider-selectable:

- Anthropic Messages API.
- OpenAI Responses API.

Each provider has its own Keychain item and model selection. The selected
provider key is preloaded once at startup and cached in memory for normal cleanup
calls.

## Storage

Slovo uses SQLite through GRDB for local personalization data:

- `vocabulary` stores spelling anchors and term weights.
- `corrections` is reserved for future correction memory.
- `profile` stores small local context facts.

The repository tracks only schema and migrations. Local databases and seed files
are never committed.

## Menu-Bar App

The app is packaged as an `LSUIElement` menu-bar app. It has no Dock icon and uses
an `NSStatusItem` for status, setup actions, provider selection, and quit.

## Build Boundaries

SwiftPM is the source of truth. All targets build with warnings as errors, strict
concurrency checking, and actor data-race checks. SwiftLint is pinned through a
SwiftPM plugin and is part of the release gate.
