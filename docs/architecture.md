# Architecture

Slovo is a native Swift menu-bar app with a small composition root and testable
core seams. The normative behavior contract (the dictation lifecycle, cleanup
on/off semantics, translate hold, empty-result and error handling, the glyph
family) lives in `AGENTS.md` → "Product intent"; this document describes the
structure and mechanisms that implement it and does not repeat that contract.

## Pipeline

The dictation flow is:

```text
key down -> start microphone + recognition; audio delivers from the first frame
ready    -> suspend delivery -> start Start cue (nothing waits on it)
cue done -> mute output (when enabled) -> resume delivery; dropped if the hold ended
key held -> convert each delivered audio chunk -> update live recognition
key up   -> stop capture -> restore output -> queue End -> finalize -> clean -> inject
```

Raw audio stays on the Mac and is transcribed on-device through WhisperKit
(Whisper large-v3 turbo); only transcript text ever leaves the machine, and only
for the OpenRouter cleanup attempt.

## Core Components

- `HotkeyMonitor` observes the configured push-to-talk key (`fn` / Globe by
  default, or a right-hand modifier); `HotkeyDecisionCore` is the pure,
  unit-tested policy that turns key events into start / stop (plain or
  translate) / silent-cancel decisions.
- `SystemAudioController` mutes and restores system output during recording, when
  the "Mute Audio While Dictating" menu setting is on (the default).
  Known limitation: a restore that the audio device rejects (for example, the
  output device disappeared mid-dictation) is swallowed, leaving output muted with
  nothing left to restore from — and cues queued afterwards, including Error, go
  into that silence. Pre-existing and accepted for now; fixing it means deciding
  what a failed restore should surface.
- `AudioRecorder` captures native microphone buffers and delivers them from the
  first frame. `suspendDelivery()`/`resumeDelivery()` bracket the readiness cue:
  each records the current host time, and the straddling callback is trimmed. A cue
  that ends almost immediately — cues off, or an asset that fails to load — still
  costs up to one callback, which is accepted rather than engineered away. Closing
  that gap does not need a reordering (which would let playback start before
  suppression is armed): it needs the boundary to CANCEL suppression back to `open`
  when the cue turns out to be inaudible, instead of ending it with a second edge.
  This excludes the cue's directly captured sound, not later acoustic echo from the
  speakers or room.
- `DictationCueController` snapshots the on-by-default Sound Cues preference per
  session and serializes Start, End, and Error through the public macOS alert-sound
  channel. Playback is never awaited by a dictation step: the readiness cue's
  completion returns as an ordinary `startCueFinished` event, and a playback
  deadline keeps a cue that never reports completion from stranding the queue.
  `OneShotAction` names the invariant that only the first caller resumes the
  continuation, so it can be raced directly from many callers released by a spin
  barrier — pinning that the guard is ATOMIC, which racing playback against the
  deadline never could: that pair's timing is bounded by wake-up precision.
  Ending a session detaches the FIFO tail, so one dictation's remaining audio never
  delays the next one's cue. End marks the end of audio recording rather than a
  successful transcription, so key-up queues it directly — after the restore, since
  End sent into muted output would not be heard — and later failures append Error
  behind it. macOS alert volume owns loudness; Slovo stores no volume value.
- `WhisperKitTranscriber` feeds audio into WhisperKit's live transcriber and
  finalizes only its unfinished tail at key-up. On a short final pass with a
  non-empty live result and no confirmed prefix, Slovo rejects a terminal
  addition only when the final decode is the exact normalized live result plus
  an anomalous suffix timestamped strictly beyond the recorded audio. The model
  remains resident between dictations.
- `WhisperKitTranscriptText.compose` guarantees the token-clean text domain in
  two layers: the compose-site sanitizer is the authoritative guarantor — every
  `finish()` outcome routes through it, stripping ASR special tokens
  (`<|...|>`) by surface form, independent of the WhisperKit version — and the
  decoder's `skipSpecialTokens` option is the first-line, token-ID-exact
  optimization. Neither the cleaner nor the paste path ever sees a special
  token.
- `Cleaner` rewrites the transcript into final prose when OpenRouter cleanup
  succeeds; `FallbackCleaner` degrades a failed attempt to `PassThrough`.
- `Injector` inserts the final text into the focused field with an atomic paste.
- `CleanupAvailability` is the app layer's single source of truth for whether
  cleanup is effectively on and, when off, why (toggled off vs. no OpenRouter
  key). The menu, Settings, the recording glyph, and the orchestrator push all
  read this one derivation (`preference && keyPresent`), so the state is never
  re-derived divergently. `CleanupAvailabilityModel` is its observed app-layer
  projection: the push funnel (`pushEffectiveCleanupConfig`) is the single
  writer, and the Settings pane observes the model instead of snapshotting at
  init, so every surface reflects an availability mutation within one runloop.
- `PersonalizationSource` supplies local vocabulary hints.
- `InputSourceLanguageReading` and `SpellCheckHintProviding` supply on-device
  cleanup hints — the active keyboard language and system spell-check
  suggestions — as advisory context for the cleanup prompt.
- `Orchestrator` owns the runtime state transitions (`DictationFsm`).
  `HotkeyEdgeSequencer` orders production key edges, and per-session identity
  prevents a resumed readiness continuation from mutating its replacement.

The app target owns OS-specific adapters and production composition. `SlovoCore`
owns the seams, value types, state machine, storage, cleanup, transcription, and
injection behavior.

## Cleanup Mechanism

Cleanup has one runtime provider: the OpenRouter Chat Completions API. The app
stores one OpenRouter key in Keychain and exposes model selection as curated
OpenRouter model ids and a custom id entry. Selecting a model changes only the
model id. The key is read lazily when cleanup runs. Before each cleanup, Slovo
adds advisory on-device hints to the prompt — the active keyboard language and,
when enabled, system spell-check suggestions — which the model may use but never
must; these hints travel to OpenRouter in the prompt alongside the transcript,
and only the raw audio never leaves the Mac.

Both prompts (cleanup and translate) are built by `PromptBuilder` around a
bundled few-shot example catalog: `PromptExampleCatalog` loads
`Resources/PromptExamples.xml` (a SwiftPM resource of `SlovoCore`) and selects
exemplars for the active language pair, including a shared language-neutral set
that teaches the model to write dictated math expressions in conventional
notation. The XML in the repository is the single source of truth for the
examples; no prompt text is assembled from string literals scattered in code.

A translate hold reuses the same single cleanup request (it also translates into
the configured target language) — there is no second pass.

## Storage

Slovo uses SQLite through GRDB for local personalization data:

- `vocabulary` stores spelling anchors and term weights.
- `corrections` and `profile` exist for migration stability; no current code
  reads or writes them.

The repository tracks only schema and migrations. Local databases and seed files
are never committed.

## Menu-Bar App

The app is packaged as an `LSUIElement` menu-bar app with no Dock icon. Its
`NSStatusItem` shows the mode glyph (see `AGENTS.md` for the glyph family,
including Nash "Ⱀ" when an update is ready) and
its dropdown holds a single live status line (carrying the hold-to-talk hint
when idle) plus an always-visible update row — **Check for Updates…** when idle
(a manual silent check), **Checking…**
during any check, then silent download progress and the hybrid **Update ready —
v… / Restart** line, rendering the pure `UpdateIndication` state folded from the
silent Sparkle pipeline. Below it sits the cleanup block: the **Clean Up
Dictation** switch, cleanup model selection, and the translate-to target
language; while no OpenRouter key is saved the whole block collapses to a single
**Add OpenRouter Key…** item that opens a dedicated key-entry window. Then come
vocabulary quick-add with adjacent mute-while-dictating and Sound Cues switches, and a bottom section
with **Settings…**, **About**, and quit; first-run setup actions replace the
dropdown until permissions are granted. The **Settings…** window covers the
push-to-talk key, recognition language, Sound Cues, launch at login, automatic
updates, cleanup model and style, translation target, OpenRouter key, and vocabulary; the
**About** window carries a quick guide and the running version. All
configuration is native windows — there are no modal alerts.

## Build Boundaries

SwiftPM is the source of truth. All Swift targets build with warnings as errors,
strict concurrency checking, and actor data-race checks; the one Objective-C
target (`SlovoObjC`, an exception-catcher shim Swift cannot express) is exempt,
since those settings do not apply to `.m` sources. SwiftLint is pinned through a
SwiftPM plugin and is part of the release gate.
