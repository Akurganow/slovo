# Cleanup benchmark

Slovo needs cleanup candidates to be compared by latency and by product quality.
The benchmark is a non-product SwiftPM executable: it is not linked into the
menu-bar app and it does not read Keychain. The OpenRouter API key can be
supplied from process environment variables or a gitignored dotenv file.

## Command

```sh
swift run --disable-automatic-resolution slovo-cleanup-benchmark \
  --env-file .env \
  --providers catalog,passthrough \
  --repetitions 10 \
  --failure-breakdown \
  --category-breakdown
```

The report is CSV-like aggregate output:

```text
candidate,runs,passed,errors,p50_ms,p95_ms
openrouter:openai/gpt-6-luna,530,473,0,908.3,1568.1
```

With `--failure-breakdown`, the command appends aggregate failure-code counts:

```text
candidate,sample_index,failure,runs
openrouter:openai/gpt-6-luna,18,sentence-structure,10
```

With `--category-breakdown`, it also appends category-level aggregate rows:

```text
candidate,category,runs,passed,errors,p50_ms,p95_ms
openrouter:openai/gpt-6-luna,punctuation-structure,120,100,0,961.2,1848.4
```

Reports intentionally do not print raw transcripts, cleaned text, prompts, API
keys, response bodies, or caller-provided sample ids.

## Sample File

`--samples` accepts either a top-level JSON array or an object with a `samples`
array:

```json
{
  "samples": [
    {
      "id": "mixed-command",
      "category": "code-switching",
      "raw": "ну вот запушь pr в github пожалуйста",
      "reference": "Запушь PR в GitHub, пожалуйста.",
      "expectation": {
        "requiredSubstrings": ["PR", "GitHub"],
        "forbiddenTerms": ["ну", "вот"],
        "preserveTokens": ["PR", "GitHub"],
        "requireTerminalPunctuation": true,
        "forbidChatResponse": true,
        "maxLengthRatio": 1.8,
        "minimumSentenceTerminators": 1,
        "maxRunOnWords": 12
      }
    }
  ]
}
```

Quality checks are deliberately not byte-identical golden outputs. They catch
the failures that matter for dictation cleanup:

- required mixed-language anchors are preserved;
- filler words and false starts selected by the sample are removed;
- forbidden filler terms are matched on token boundaries, so `ну` does not fail
  inside legitimate words such as `нужно`;
- chat-style answers are rejected;
- terminal punctuation is present when expected;
- longer samples have enough sentence boundaries when requested;
- long run-on segments can be capped with `maxRunOnWords`;
- the output is not wildly longer than the input.

The default suite is pinned at `Benchmarks/cleanup/slovo-cleanup-v1.json`. It has
53 synthetic/public-style samples, grouped as:

| Category | Count |
| --- | ---: |
| `short-smoke` | 4 |
| `russian-filler` | 6 |
| `code-switching` | 9 |
| `punctuation-structure` | 12 |
| `commands-editor` | 4 |
| `inverse-text-normalization` | 7 |
| `safety-negative` | 8 |
| `instruction-shaped-transcript` | 3 |

The `instruction-shaped-transcript` category is the permanent tripwire for the
executed-dictation failure class: long task-shaped dictations (the flagship is a
1,557-char RU+EN brief addressed to an assistant) whose expectations reject an
executed answer — headings the speaker never said, chat-style replies, few-shot
tag echoes — while accepting the speaker's own words cleaned per the rules.

The default benchmark does not download datasets or models at runtime.

## Providers

The benchmark accepts three provider forms:

- `openrouter:<model-id>` sends transcript text to OpenRouter with the selected
  routed model id and requires `OPENROUTER_API_KEY`.
- `catalog` expands to one `openrouter:` form per model in the app's cleanup
  catalog, `CleanupModelCatalog`, in menu order.
- `passthrough` preserves the raw transcript locally and provides a latency and
  quality floor. It is also the raw-mode (cleanup disabled) baseline: raw mode
  short-circuits the whole cleaner stage (the orchestrator skips hint-gathering
  and the cleaner), and `passthrough`, a no-op cleaner, is the closest
  harness-measurable proxy for that skipped stage's ~0 ms cost (see
  "No-cleanup (raw) baseline" below).

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

## Latest Live Snapshot

Live benchmark of the curated shortlist, measured on 2026-10-08 with 10
repetitions over the 53-sample suite: temperature 0, the transcript in
`<transcript>` tags, reasoning disabled via `reasoning: {effort: "none"}`, and
the shipped prompt.
Prompt coverage, stated plainly: the harness passes no on-device hints, so the
measured prompt is the current base instruction set WITHOUT the
keyboard-language prior — that advisory line fires only in the app, when a
gathered hint carries the active input locale. Compare runs by pass RATE
(passed/runs), never by raw passed counts.

| Candidate | Runs | Passed | Errors | p50 | p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `openrouter:openai/gpt-6-luna` | 530 | 480 | 0 | 931.4 ms | 2118.5 ms |
| `openrouter:deepseek/deepseek-v4.1-flash` | 530 | 451 | 0 | 348.4 ms | 1380.2 ms |
| `openrouter:anthropic/claude-haiku-5.5` | 530 | 446 | 0 | 546.8 ms | 1140.0 ms |
| `openrouter:minimax/minimax-m3` | 530 | 434 | 0 | 1513.3 ms | 2915.8 ms |
| `openrouter:google/gemini-3.1-flash-lite` | 530 | 400 | 45 | 5666.8 ms | 26726.5 ms |
| `openrouter:mistralai/mistral-small-2603` | 530 | 313 | 154 | 430.9 ms | 1057.3 ms |
| `passthrough:none` (raw mode) | 530 | 0 | 0 | 0.0 ms | 0.0 ms |

- Claude Haiku 4.5, the model Haiku 5.5 replaced, passed 410 of 530 at
  1006.1 ms p50 and 1997.6 ms p95 on 2026-09-27, under the earlier prompt
  wording. Haiku 5.5 passes every
  inverse-text-normalization and short-smoke run. Its weak spot is
  russian-filler, 20 of 60: it keeps the fillers "ну", "вот" and "короче".
- Qwen3.8 Flash was not measured in this run. Its only full run is in the
  catalog refresh below.
- The report records the Gemini and Mistral errors as provider errors,
  without their HTTP status.

### Prompt change of 2026-09-27

The plain cleanup prompt gained three rules: a percentage example in the
number rule, separate sentences for independent statements with no connecting
word, and a request for text in another language kept as dictated content.
Translate mode gains only the percentage example. The sentence rule's example
output stays in the source language, which would model an untranslated answer.

The side-by-side run below measured an earlier wording, which an independent
review then corrected in three places:

- The number rule read "numbers, dates, times, and percentages in written
  form". It now keeps "number, date, and time phrases in conventional written
  form", so counts such as "two bullet points" are not invited into digits.
- The language line ended "keep the output in the speaker's language", which
  could push English terms out of RU+EN speech. It now ends as the older rule
  does: "keep every word in the language the speaker used".
- Translate mode carried the sentence rule; it no longer does.

A later probe of the shipped prompt passed every targeted sample: DeepSeek
V4.1 Flash samples 25, 38 and 51 (5 of 5 each), GPT-6 Luna sample 51 (10 of
10), Gemini sample 51 (5 of 5), and MiniMax samples 11, 12, 29 and 48 (5 of 5
each).

The old and earlier-wording prompts ran side by side, at the same time:

| Model | Old prompt | New prompt |
| --- | ---: | ---: |
| `openai/gpt-6-luna` | 476 | 484 |
| `deepseek/deepseek-v4.1-flash` | 426 | 452 |
| `minimax/minimax-m3` | 448 | 441 |
| `google/gemini-3.1-flash-lite` | 440 | 430 |
| `qwen/qwen3.6-flash` | 415 | 420 |
| `anthropic/claude-haiku-4.5` | 400 | 410 |

Passed runs of 530. DeepSeek V4.1 Flash fixed sample 25 ("15%"), sample 38
(three statements, three sentences) and sample 51 (the long instruction-shaped
dictation). Gemini lost 10 runs on sample 51 by writing "Steps to Reproduce" in
title case. MiniMax's net loss of 7 runs was spread over many samples, gains
included. In code-switching it fell from 87 to 78 of 90, on samples 11, 12 and
48. Neither loss reproduced in a later probe of that wording: Gemini passed
sample 51 in 5 of 5 runs, and MiniMax passed samples 11, 12, 29 and 48 in 10
of 10 runs each. Code-switching rose from 88 to 90 of 90 for GPT-6 Luna and
from 59 to 62 for Qwen3.6 Flash, and did not change for the other three
models.

### Catalog refresh of 2026-09-27

Successor candidates against the models they would replace, measured on
2026-09-27 under the prompt before the change above:

| Candidate | Runs | Passed | Errors | p50 | p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `openrouter:openai/gpt-5.6-luna` (replaced) | 530 | 459 | 0 | 993.4 ms | 1688.1 ms |
| `openrouter:openai/gpt-6-luna` | 530 | 473 | 0 | 908.3 ms | 1568.1 ms |
| `openrouter:deepseek/deepseek-v4-flash` (replaced) | 530 | 434 | 0 | 1756.3 ms | 2389.7 ms |
| `openrouter:deepseek/deepseek-v4-flash-0731` | 530 | 438 | 0 | 348.1 ms | 1328.5 ms |
| `openrouter:deepseek/deepseek-v4.1-flash` | 530 | 429 | 0 | 255.6 ms | 498.8 ms |
| `openrouter:qwen/qwen3.6-flash` (replaced) | 530 | 420 | 0 | 660.6 ms | 1064.9 ms |
| `openrouter:qwen/qwen3.7-flash` | 530 | 390 | 25 | 934.9 ms | 1788.0 ms |
| `openrouter:qwen/qwen3.8-flash` | 530 | 217 | 277 | 2207.0 ms | 7389.5 ms |

- GPT-6 Luna replaced GPT-5.6 Luna as the default: more passes (code-switching
  89 of 90 against 84), lower p50 and p95, and a lower OpenRouter price
  ($0.20 → $0.10 per 1M input tokens, $1.20 → $0.50 output).
- DeepSeek V4.1 Flash replaced DeepSeek V4 Flash by the owner's decision,
  though it passed 5 fewer runs under the old prompt: p50 fell from 1756 ms to
  256 ms, and the instruction-shaped samples went from 20 to 30 of 30. Under
  the new prompt it passes 452.
- DeepSeek V4 Flash 0731 was left out: a code-switching-only rerun at 20
  repetitions passed 175 of 180, against 180 for both V4 Flash and V4.1 Flash.
- Qwen3.8 Flash replaced Qwen3.6 Flash by the owner's decision. Of the 253
  requests it answered, 217 passed: 86%, against 79% for Qwen3.6 Flash. The
  other 277 failed with HTTP 429 from Alibaba, its only provider. The owner
  judged that a product of the benchmark's steady request stream, which
  dictation does not produce. A later probe got 2 answers in 5 calls, at 3.5
  and 5.9 s. Qwen3.7 Flash passed fewer runs than Qwen3.6 Flash.
- Gemini 3.1 Flash Lite stays: Gemini 3.5 Flash Lite cannot run with
  reasoning off.

### No-cleanup (raw) baseline

Raw mode (cleanup toggled off) short-circuits the whole cleaner stage — the
orchestrator skips hint-gathering and the cleaner, not just the network call;
`passthrough`, a no-op cleaner, is the closest harness-measurable proxy for
that skipped stage's ~0 ms cost. Measured on 2026-09-27 (10 repetitions over
the 53-sample suite; the passthrough candidate itself needs no API key and no
network):

| Candidate | Runs | Passed | Errors | p50 | p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `passthrough:none` (raw mode) | 530 | 0 | 0 | 0.0 ms | 0.0 ms |

> What this number covers (noted 2026-07-23): cleaner-stage time only — the
> in-process call the harness times for every candidate. The harness does NOT
> measure WhisperKit tail finalization or the paste into the focused app; the
> end-to-end key-up→inserted latency of raw mode is an owner-runbook
> measurement, not a harness number. This row is a documented baseline for
> reading the cleanup-model latencies above; it does not gate CI. `Passed 0`
> is expected: the quality expectations describe cleaned text, and raw
> transcripts fail them by design (the quality floor). For cross-version
> comparisons, compare by pass rate, never by raw passed counts.

The end-to-end number is captured OUTSIDE the harness, from the app's own
timing marks: `dictation.stopRequested` at key-up (Orchestrator) and
`injection.pasted` right after the paste keystroke (ClipboardPasteInjector),
both in the `com.slovo.app` / `dictation` log category. Procedure: launch the
signed dev build with cleanup off, run one dictation, then:

```sh
log show --last 5m --style json \
  --predicate 'subsystem == "com.slovo.app" AND category == "dictation" AND (eventMessage == "dictation.stopRequested" OR eventMessage == "injection.pasted")'
```

The latency is `timestamp(injection.pasted) − timestamp(dictation.stopRequested)`.
The paste mark deliberately precedes the 300 ms clipboard-restore delay, which
is not user-visible latency. Template, to be filled from the runbook
measurement:

> End-to-end (runbook measurement, this development Mac, 2026-MM-DD): with
> cleanup off, key-up → text inserted measured at NNN ms (single live
> dictation, real pipeline: WhisperKit tail finalization + clipboard paste;
> delta between the `dictation.stopRequested` and `injection.pasted` log
> marks). Real-pipeline number on this Mac, distinct from the harness's
> cleaner-stage column above; not a CI gate.

### Cleanup model reference numbers

Public reference numbers for the curated catalog models. Retrieved 2026-07-12.
Sources: OpenRouter catalog API (pricing), Artificial Analysis Intelligence
Index v4.1 leaderboard (intelligence, output speed, first-answer-token latency),
AA-Omniscience hallucination rates via the BenchLM aggregator (medium extraction
confidence). Cleanup does not use reasoning mode, so the table shows
non-reasoning figures; `n/a` marks values published only for reasoning mode or
models absent from the leaderboard.

| Model | Price in/out, $/1M | Intelligence Index | Hallucination rate | Output speed | First-token latency |
| --- | ---: | ---: | ---: | ---: | ---: |
| `openai/gpt-6-luna` (default) | 0.10 / 0.50 | — | — | — | — |
| `anthropic/claude-haiku-5.5` | 0.10 / 0.50 | — | — | — | — |
| `google/gemini-3.1-flash-lite` | 0.25 / 1.50 | 25 | 81.6% | 294 t/s | 5.2 s |
| `qwen/qwen3.8-flash` | 0.15 / 0.47 | — | — | — | — |
| `deepseek/deepseek-v4.1-flash` | 0.035 / 0.29 | — | — | — | — |
| `mistralai/mistral-small-2603` | 0.15 / 0.60 | 20 | 66.8% | 173 t/s | 0.81 s |
| `minimax/minimax-m3` | 0.30 / 1.20 | n/a | n/a | n/a | n/a |

`n/a` means the model is absent from that public leaderboard as of the retrieval
date. `—` marks the rows added on 2026-09-27 and 2026-10-08: their price
comes from the OpenRouter catalog API on the day each was added, and their
leaderboard columns were not retrieved. Public multilingual leaderboards (Global-MMLU-Lite, MMMLU) do not cover
Russian, so Russian-specific quality is not represented by any number above; the
`slovo-cleanup-v1` suite is the project's own measurement on dictation-style
samples.

## Sources

- OpenRouter API docs: https://openrouter.ai/docs
- OpenRouter Chat Completions API: https://openrouter.ai/docs/api-reference/chat-completion
- OpenRouter model list API: https://openrouter.ai/api/v1/models

## Verification

PASS — refreshed on 2026-10-08 with a live 10-repetition run of the curated
shortlist over the 53-sample suite, using the current cleanup request and the
shipped prompt. Qwen3.8 Flash was not measured in that run. The prompt-change
and catalog-refresh tables and the no-cleanup (raw) baseline come from the
2026-09-27 runs.
