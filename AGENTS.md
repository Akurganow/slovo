# Agent & contributor guide

This file is the shared brief for anyone changing Slovo — human contributor or AI
coding agent. It follows the [agents.md](https://agents.md) convention: it states
what the app must do and the invariants a change must never break. For the human
workflow (setup, tests, packaging, the pull-request checklist) see
[CONTRIBUTING.md](CONTRIBUTING.md); for the licensing terms see
[LICENSE](LICENSE).

## Product intent — how the app must work

Slovo is a private, on-device push-to-talk dictation app for macOS. One dictation:

1. **Key down** — microphone capture AND speech recognition both start immediately.
2. **While the key is held** — recognition receives audio continuously and
   transcribes live (low latency).
3. **Key up** — the transcript is already ready, or nearly ready.
4. **Immediately after key up** — text cleanup runs (via OpenRouter).
5. **Cleanup is always attempted.** The raw transcript is inserted directly ONLY on
   a genuine cleanup failure (unavailable / refused / misconfigured / provider or
   network error) — NEVER because a setting disabled cleanup.
6. The final cleaned text is inserted into the focused app.

Clarifications:

- **"Live" means LOW LATENCY (text ready at key-up), NOT a visible running
  transcript.** No overlay, no partial text on screen. Only the final cleaned text
  is inserted (raw only on cleanup failure).
- **Translate hold.** Holding the push-to-talk key together with Control at any
  moment of the hold makes that one dictation translate: the single cleanup step
  also translates the result into the target language chosen in Settings or the
  menu-bar dropdown, then inserts it. A plain hold (no Control) must never
  translate.
- **Translate hold glyph.** While a translate hold is active (Control latched at
  any moment during the push-to-talk hold), the recording glyph is the Glagolitic
  letter Pokoji "Ⱂ" (U+2C12) instead of the plain recording glyph Zemlja "Ⰸ"
  (U+2C08); it switches live the moment Control latches, so the mode is visible at
  a glance.
- **Mute while dictating.** A menu-bar switch (on by default) silences system
  audio output while the key is held and restores it afterward; turning it off
  leaves system audio untouched during dictation.
- **Empty result** (key held but only silence): the menu bar briefly shows the
  red failure glyph "Ⱁ" (U+2C11), nothing is inserted, and there is no alert and
  no persistent notice — do not distract the user.
- **Errors surface only through the menu-bar icon/status** — never an alert,
  dialog, or focus-stealing notification. Slovo types into the user's current app;
  stealing focus destroys the workflow it exists to serve.
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

### Before you open a pull request

- Run `Scripts/diagnose.sh` (build, tests, and strict lint as independent stages).
- Keep raw audio local; only transcript text may leave the machine, and only for
  cleanup.
- Never commit secrets, local databases, seed files, or signing material.
- Update the docs when user-visible behavior, setup, privacy, or the release
  workflow changes.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full checklist and commands.
