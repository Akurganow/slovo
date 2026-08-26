# Agent & contributor guide

This file is the shared brief for anyone changing Slovo — human contributor or AI
coding agent. It follows the [agents.md](https://agents.md) convention: it states
what the app must do and the invariants a change must never break. For the human
workflow (setup, tests, packaging, the pull-request checklist) see
[CONTRIBUTING.md](CONTRIBUTING.md); for the licensing terms see
[LICENSE](LICENSE).

## Standing owner directives

Non-negotiable working rules from the project owner, recorded here so they never
have to be repeated. Every agent and contributor follows them without being asked.

1. **Refactoring bar.** A refactoring must shrink the code OR shrink cognitive
   load; the two must never both grow in one change. At least one strictly
   decreases.
2. **Legacy dies in the same commit that makes it legacy.** Never park removed or
   superseded code "on disk pending deletion approval" — no build-excluded
   corpses, no "delete later" comments. The change that makes something legacy
   deletes it.
3. **The owner manually verifies every deliverable.** After independent audit,
   integrate the verified work into local main and produce the dev build via the
   approved launcher (see below), then hand it to the owner for a manual check.
   Work is not done until the owner has a runnable dev build.
4. **Design attractor: data-driven.** Prefer directions that centralize state as
   data and derive views/effects as projections of it (reducers/selectors idiom:
   view = f(state), a single mutation path, effects as data). An attractor, not a
   straitjacket — but when several designs fit, pick the one that moves this way.
5. **Milliseconds never justify complexity; reliability does.** A mechanism whose
   only benefit is shaving time off an edge case is not worth building. A
   mechanism that makes the app safer or more reliable earns its keep — but the
   more moving parts, the likelier the failure, so always prefer the smallest
   mechanism that delivers the reliability.

## Product intent — how the app must work

Slovo is a private, on-device push-to-talk dictation app for macOS. One dictation:

1. **Key down** — microphone capture AND speech recognition both start immediately.
2. **While the key is held** — recognition receives audio continuously and
   transcribes live (low latency).
3. **Key up** — the transcript is already ready, or nearly ready.
4. **Immediately after key up** — text cleanup runs (via OpenRouter).
5. **Cleanup is always attempted while the cleanup setting is on (the default).**
   With cleanup on, the raw transcript is inserted directly only on a genuine
   cleanup failure (unavailable / refused / misconfigured / provider or network
   error). Raw-by-choice is a first-class mode, not a failure: with the "Clean
   Up Dictation" toggle off (menu bar or Settings) — or with no OpenRouter key
   configured, which is the same effective off mode automatically — the raw
   final transcript is inserted once at key-up with zero network requests;
   translation is unavailable there.
6. The final text — cleaned when cleanup is on, raw in raw mode — is inserted
   into the focused app.

Clarifications:

- **"Live" means LOW LATENCY (text ready at key-up), NOT a visible running
  transcript.** No overlay, no partial text on screen. In BOTH modes the final
  text is inserted exactly once at key-up: the cleaned text while cleanup is on
  (raw only on a genuine cleanup failure), the raw final transcript in raw mode.
- **Translate hold.** Translation is driven by a configurable **translate key**
  (Control by default), drawn from the same pool as the push-to-talk key and
  never the same key — the two settings are mutually exclusive. By default it is
  an *additional* key: press it at any moment while the push-to-talk key is down
  and that one dictation translates. Slovo sees ⌃ and fn in every keystroke, so
  they also count when already down as the hold begins; a sided ⌘, ⌥ or ⇧ is
  noticed only when that key itself moves, so it must go down during the hold.
  With "Use as additional key" off it is *standalone* — a push-to-talk key of
  its own whose every dictation translates, while the main key keeps dictating
  plainly. Either way the single cleanup step also translates the result into
  the target language chosen in Settings or the menu-bar dropdown, then inserts
  it. A plain hold (translate key untouched) must never translate, and translate
  requires cleanup to be effectively on — while cleanup is off, the translate
  key adds no translation to the dictation. The defaults preserve today's
  behavior exactly.
- **Recording glyph family.** The recording glyph names the mode: the Glagolitic
  letter Cherv "Ⱍ" (U+2C1D) while a plain hold records with cleanup on, Glagoli
  "Ⰳ" (U+2C03) while cleanup is effectively off (raw mode, either cause), and
  Pokoji "Ⱂ" (U+2C12) while a dictation is set to translate — from the moment an
  additional translate key joins the hold (live, mid-hold), or from key-down for a
  standalone translate hold, so the mode is visible at a glance. Raw wins over
  translate: with cleanup off the glyph stays Glagoli. The resting idle glyph
  shows Slovo "Ⱄ" (U+2C14) normally, swapping to Nash "Ⱀ" (U+2C10) while a
  downloaded update awaits Restart. The failure glyph "Ⱁ" (U+2C11) is unchanged.
- **Mute while dictating.** A menu-bar switch (on by default) silences system
  audio output while the key is held and restores it afterward; turning it off
  leaves system audio untouched during dictation.
- **Sound cues.** A switch in Settings → General and beside Mute in the menu-bar
  dropdown is on by default.
  - **Cues are fire-and-forget: no dictation step ever waits on audio.** A cue that
    plays late, fails, or never reports completion must never delay the microphone,
    the key-up, or the text pipeline — while still playing reliably itself.
  - Once capture and recognition are ready, Start plays and captured audio is
    withheld across it, so the cue is not transcribed. This is a software boundary,
    not echo cancellation: the cue's acoustic tail in the room is not removed.
  - Speech from before the cue — including while the speech model loads — still
    reaches recognition, minus up to one capture callback around the cue. With cues
    off that callback is the whole cost, and it is accepted rather than engineered
    away.
  - Output is muted once Start is done; a hold that ended first drops that mute
    instead of silencing audio after the fact. A cue that never reports completion
    is released by a deadline, at the price of audio staying withheld until it
    elapses — the deliberate trade for never stranding the pipeline.
  - **End marks the end of AUDIO RECORDING, not a successful transcription.** At
    key-up Slovo stops capture, restores output, and queues End right there, so the
    sound lands with the glyph change instead of trailing the transcript. It is
    queued after the restore, since End sent into muted output would not be heard,
    and never delays cleanup or translation.
  - Any failure after the recording ended — silence, finalization, cleanup, or
    insertion — adds Error behind End through the same FIFO; a failure before it
    ended produces Error alone. Intentional cancellation is silent, with neither End
    nor Error.
  - The queue is per-dictation, so one dictation's remaining audio never delays the
    next one's cue and back-to-back cues may briefly overlap — deliberately, since
    delaying the microphone is the worse outcome.
  - Cue loudness follows the macOS system alert volume — Slovo has no volume
    setting.
- **Empty result** (key held but only silence): the menu bar briefly shows the
  red failure glyph "Ⱁ" (U+2C11), nothing is inserted, and cleanup is never
  called — an empty or whitespace-only transcript must reach neither OpenRouter
  nor the pasteboard. There is no alert dialog or persistent notice; when Sound
  Cues is on, the non-focus-stealing Error cue accompanies the glyph.
- **Errors surface through the menu-bar icon/status and the optional Error audio
  cue** — never an alert dialog or focus-stealing notification. Slovo types into
  the user's current app; stealing focus destroys the workflow it exists to serve.
- Runs fully on-device for recognition (privacy). Must recognize mixed RU + English
  within a single utterance at quality at least the current Whisper large-v3 level
  (see principles).

## Non-negotiable principles

1. **Intent is primary.** Understand the *real* intent behind a request or issue.
   Never reinterpret, substitute, or "translate" it into a more convenient concept.
   If the intent is genuinely ambiguous, ask before building — do not
   guess-and-assemble.

2. **Do not react — engineer.** Do not jam the intent into the first
   implementation that seems to fit. That is not engineering.

3. **Prepare before acting.** Real engineering starts with preparation: formulate
   the task/problem explicitly, establish the full requirement set, research the
   reality, and evaluate options against the requirements *with evidence*. Only
   then act. Do not run to demolish.

4. **Do not replace a component without proof.** Do not swap out a working
   component (e.g. the ASR engine) unless you have proven both that the change is
   *necessary* and that the replacement is the *best* choice for the task.

5. **"Do not break" is implicit in every task.** "Do not break" ≠ "break and then
   fix." Never degrade working functionality as a step toward a goal.

6. **Do not regress quality.** Recognition/output quality must be at least as good
   as the current baseline. For Slovo specifically: mixed Russian + English within
   a single utterance (RU+EN intra-utterance code-switching) must keep working, as
   it does today; recognition quality must be at least the current Whisper
   large-v3 level.

7. **Ground decisions in evidence.** Read the official documentation. Do not assert
   confidently without proof; state what you actually checked and what remains
   unverified.

8. **Communicate in plain, behavior-level language** — describe behavior the user
   observes, not internal code or jargon.

## Engineering process

### User-testable app on this development Mac — one approved build path

When building an app for the user to test on this development Mac, use only the
repository launcher with the exact stable Developer ID identity already
installed in the macOS Keychain:

```sh
SIGNING_IDENTITY="Developer ID Application: Alexander Kurganov (ZN8H5SF4R7)" \
  Scripts/build_and_run.sh --verify
```

Do not substitute ad-hoc signing, another local-development identity, a raw
SwiftPM executable, or a hand-built app bundle. Before asking the user to test,
verify that `.build/dev-run/Slovo.app` passes strict code-sign validation, is
signed by team `ZN8H5SF4R7`, has bundle identifier `com.slovo.app`, and that the
running `slovo` process executes from that exact bundle.

### Gate RED→GREEN by Cynefin

Before starting a RED→GREEN cycle, classify the change with Cynefin and decide
whether the cycle is warranted at all:

- **Clear/Obvious domain** — an elementary edit whose correctness is directly
  observable (one wire field, a constant, a list entry, a doc line): skip the
  RED→GREEN ceremony. Make the change and verify it directly — a focused
  assertion, a one-shot live check against the real dependency, or plain
  inspection. Example: adding `reasoning: {effort: "none"}` to the OpenRouter
  request body, verified by one live call per catalog model.
- **Complicated/Complex domain** — behavior can regress invisibly, interactions
  or concurrency are involved, or the failure mode is not directly observable:
  full RED→GREEN applies (proven-red test first, then the fix).

### Tests must be able to fail

Whenever a test is written (either path above), it must be demonstrably able to go
red on broken code. A test that stays green on both the correct and a mutated
implementation proves nothing — prove RED before GREEN, and document the concrete
breakage each regression test catches.

### The endpoint of feature work is a verified commit on local main

A feature is DONE only when it lands as a verified commit on LOCAL main —
implementer branches → independent audit (correctness, complexity, design,
test sensitivity) → full gates (`Scripts/diagnose.sh`) on the integrated
result → merge into local main. Parked branches are not a deliverable.
Pushing to any remote remains a separate act, triggered only by the owner.

### License compliance is part of every change

Slovo is GPLv3. Any change that adds, removes, or updates a dependency,
bundles a new resource, or brings in external code must keep the license
posture correct IN THE SAME CHANGE: verify the component's license is
GPLv3-compatible, and keep the third-party notices artifact (and the
README license section) current so every shipped component's copyright and
permission notice travels with the binary. Never vendor code or assets
whose license is unknown or incompatible (e.g. PolyForm Noncommercial —
a real trap already caught once: Lightning-SimulWhisper).

### Before you open a pull request

- Run `Scripts/diagnose.sh` (build, tests, and strict lint as independent stages).
- Keep raw audio local; only transcript text may leave the machine, and only for
  cleanup — plus the key-scope metadata request to OpenRouter (`/models/user`),
  which carries the API key and no user content.
- Never commit secrets, local databases, seed files, or signing material.
- Update the docs when user-visible behavior, setup, privacy, or the release
  workflow changes.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full checklist and commands.
