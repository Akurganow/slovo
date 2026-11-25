# Cleanup benchmark

Slovo needs cleanup candidates to be compared by latency and by product quality.
The benchmark is a non-product SwiftPM executable: it is not linked into the
menu-bar app and it does not read Keychain. The OpenRouter API key can be
supplied from process environment variables or a gitignored dotenv file.

## Command

```sh
swift run --disable-automatic-resolution slovo-cleanup-benchmark \
  --env-file .env \
  --providers catalog \
  --judge \
  --baseline Benchmarks/cleanup/baseline.json \
  --failure-breakdown \
  --category-breakdown
```

The report is CSV-like aggregate output. Without `--judge` it holds the fuzzy
coefficient only and no verdict:

```text
candidate,runs,failed_runs,p50_ms,p95_ms,fuzzy,embedding,jev,cost_usd
openrouter:<model>,275,0,<p50>,<p95>,<mean>,,,<cost>
```

With `--judge` the embedding and Jev means fill in, and a line names the judge's
response models and its cost. With `--baseline` the report adds one row per
candidate and per category: samples, misses, allowed misses, dropped repetitions
above the entry's slack plus the floor on any coefficient, the three means, and
`pass` or `fail`.

With `--failure-breakdown`, the command appends aggregate failure-code counts
(`provider-error`, `empty-output`, `embedding-failed`, `jev-refusal`, `jev-request-failed`) by sample index. With
`--category-breakdown`, it also appends category-level rows.

Reports intentionally do not print raw transcripts, cleaned text, references,
prompts, API keys, response bodies, or caller-provided sample ids. The opt-in
`--outputs-file PATH` is the one place output text is written, as JSON lines: one
after a run's cleanup and one after it is judged.

The exit code reflects each candidate's bar against its own entry only: a fail against
the `--baseline-candidate` fallback entry alone still exits 0. `Benchmarks/cleanup/README.md`,
"Running the judge", lists the codes. The command never prompts, and the key comes from
the environment or `--env-file`.

## Sample File

`--samples` accepts either a top-level JSON array or an object with a `samples`
array. Each sample has an `id`, an optional `category`, the `raw` dictation and
`references`, a non-empty list: the first is the expected cleanup, the others are
equally valid forms of it. Other keys are ignored.

```json
{
  "samples": [
    {
      "id": "mixed-command",
      "category": "code-switching",
      "raw": "ну вот запушь pr в github пожалуйста",
      "references": ["Запушь PR в GitHub, пожалуйста."]
    }
  ]
}
```

## Judge

Each output is scored against the sample's references by three coefficients
(fuzzy, embedding, Jev). `Benchmarks/cleanup/README.md`, "What a pass means",
holds the plain account, the bar and the flags; the settings live in
`Benchmarks/cleanup/judge.json`. What the code adds to that:

- The fuzzy coefficient is RapidFuzz `token_sort_ratio` over the words, so word
  order never matters. The texts are lowercased, `ё` is read as `е`, and every
  character that is not a letter, a number or a combining mark becomes a space.
  Apple's word tokenizer splits the result, so Chinese, Japanese and Thai split
  into words. Each distinct `Character` of the two texts becomes one integer id,
  so a letter with its combining marks counts once. The library is vendored in
  `Tools/cleanup-benchmark-fuzz` (rapidfuzz-cpp, MIT; release, commit and
  SHA-256 in `VENDORED.txt` beside it) because upstream ships no `Package.swift`.
- A refused Jev question is a judge error for that output, never a score. The
  failure codes in `--failure-breakdown` are `provider-error`, `empty-output`,
  `embedding-failed`, `jev-refusal` and `jev-request-failed`.
- The only lexical check left is `empty-output`.

The default suite is pinned at `Benchmarks/cleanup/slovo-cleanup-v1.json`. It has
55 synthetic/public-style samples, grouped as:

| Category | Count |
| --- | ---: |
| `short-smoke` | 5 |
| `russian-filler` | 6 |
| `code-switching` | 10 |
| `punctuation-structure` | 12 |
| `commands-editor` | 4 |
| `inverse-text-normalization` | 7 |
| `safety-negative` | 8 |
| `instruction-shaped-transcript` | 3 |

The `instruction-shaped-transcript` category is the permanent tripwire for the
executed-dictation failure class: long task-shaped dictations (the flagship is a
1,557-char RU+EN brief addressed to an assistant) that an assistant would answer
instead of clean. The judge's `adds_nothing` question catches an executed answer,
a chat reply or a few-shot tag echo.

The default benchmark does not download datasets or models at runtime.

## Providers

The benchmark accepts three provider forms:

- `openrouter:<model-id>` sends transcript text to OpenRouter with the selected
  routed model id and requires `OPENROUTER_API_KEY`.
- `catalog` expands to one `openrouter:` form per model in the app's cleanup
  catalog, `CleanupModelCatalog`, in menu order.
- `passthrough` preserves the raw transcript locally and provides a latency
  floor. It is also the raw-mode (cleanup disabled) baseline: raw mode
  short-circuits the whole cleaner stage (the orchestrator skips hint-gathering
  and the cleaner), and `passthrough`, a no-op cleaner, is the closest
  harness-measurable proxy for that skipped stage's ~0 ms cost (see
  "Raw-mode end-to-end latency" below).

A model enters the catalog only if reasoning can be switched off, because
every cleanup request sends `reasoning: {effort: "none"}` to keep key-up
latency low. OpenRouter publishes this per model in `GET /api/v1/models`: a
model whose `reasoning.mandatory` is `true` rejects the request with HTTP 400,
"Reasoning is mandatory for this endpoint and cannot be disabled". On
2026-09-27 that ruled out `google/gemini-3.5-flash-lite`,
`google/gemini-3.8-flash`, `z-ai/glm-5.3-flash` and `z-ai/glm-5.3-flashx`. At
its lowest allowed effort, `low`, GLM 5.3 Flash spent 1283–2288 reasoning
tokens and 54–102 s on the suite's longest dictation (sample 51, under a
short probe prompt). Every catalog model answered a probe with
`reasoning: {effort: "none"}` using 0 reasoning tokens.

## Results

This document keeps no results. Each catalogue model's recorded slack per sample
is in `Benchmarks/cleanup/baseline.json`, which the cleanup benchmark workflow
writes (`docs/release-ci.md`, "Cleanup benchmark"). Latency, failed calls, the
means, the cleanup and judge cost and the verdicts are in the run's report: its
job log, and `report.csv` in its `cleanup-baseline` artifact, kept for seven days.
The earlier result tables, scored by the removed lexical gate, are in this file's
version-control history.

## Raw-mode end-to-end latency

Raw mode (cleanup toggled off) skips the whole cleaner stage: the orchestrator
skips hint-gathering and the cleaner, not just the network call. `passthrough`
times only that skipped stage, about 0 ms. It does not measure WhisperKit tail
finalization or the paste into the focused app, so raw mode's key-up to inserted
latency is measured outside the harness, from the app's own timing marks:
`dictation.stopRequested` at key-up (Orchestrator) and `injection.pasted` right
after the paste keystroke (ClipboardPasteInjector), both in the `com.slovo.app` /
`dictation` log category. Procedure: launch the signed dev build with cleanup
off, run one dictation, then:

```sh
log show --last 5m --style json \
  --predicate 'subsystem == "com.slovo.app" AND category == "dictation" AND (eventMessage == "dictation.stopRequested" OR eventMessage == "injection.pasted")'
```

The latency is `timestamp(injection.pasted) − timestamp(dictation.stopRequested)`.
The paste mark deliberately precedes the 300 ms clipboard-restore delay, which
is not user-visible latency. It is a live measurement on one Mac, not a CI gate.

## Sources

- OpenRouter API docs: https://openrouter.ai/docs
- OpenRouter Chat Completions API: https://openrouter.ai/docs/api-reference/chat-completion
- OpenRouter model list API: https://openrouter.ai/api/v1/models
