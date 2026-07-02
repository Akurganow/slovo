# slovo — Agent Instructions

> Minimal working set of the constraints the user has stated. Work in progress —
> to be expanded and curated manually. The user's global rules
> (`~/.claude/CLAUDE.md`) still apply on top of this file.

## Product intent — how the app must work

slovo is a private, on-device push-to-talk dictation app for macOS. One dictation:

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
- **Empty result** (key held but only silence, no error): briefly show the
  Glagolitic letter Nashi "Ⱀ" (U+2C10) in the menu bar, insert nothing, show no
  alert and no persistent notice — do not distract the user. This is NOT an error,
  and is distinct from a genuine recognition failure (which is surfaced honestly).
- Runs fully on-device (privacy). Must recognize mixed RU + English within a single
  utterance at quality at least the current Whisper large-v3 level (see principles).

## Non-negotiable principles

1. **Intent is primary.** Understand the user's *real* intent. Never reinterpret,
   substitute, or "translate" it into a more convenient concept. If the intent is
   genuinely ambiguous, ask before building — do not guess-and-assemble.

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
   as the current baseline. For slovo specifically: mixed Russian + English within
   a single utterance (RU+EN intra-utterance code-switching) must keep working, as
   it does today; recognition quality must be at least the current Whisper
   large-v3 level.

7. **Ground decisions in evidence.** Read the official documentation. Do not assert
   confidently without proof; state what you actually checked and what remains
   unverified.

8. **Communicate in plain, behavior-level language** — describe behavior the user
   observes, not internal code or jargon.

## Process — gate RED→GREEN by Cynefin

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

Whenever a test IS written (either path), the false-green rules still apply in
full: the test must be demonstrably able to go red on broken code.
