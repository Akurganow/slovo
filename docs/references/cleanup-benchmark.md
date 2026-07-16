# Cleanup benchmark

Slovo needs cleanup candidates to be compared by latency and by product quality.
The benchmark is a non-product SwiftPM executable: it is not linked into the
menu-bar app and it does not read Keychain. The OpenRouter API key can be
supplied from process environment variables or a gitignored dotenv file.

## Command

```sh
swift run --disable-automatic-resolution slovo-cleanup-benchmark \
  --env-file .env \
  --providers openrouter:openai/gpt-5.6-luna,openrouter:anthropic/claude-haiku-4.5,openrouter:google/gemini-3.1-flash-lite,openrouter:qwen/qwen3.6-flash,openrouter:deepseek/deepseek-v4-flash,openrouter:mistralai/mistral-small-2603,openrouter:minimax/minimax-m3,passthrough \
  --repetitions 10 \
  --failure-breakdown \
  --category-breakdown
```

The report is CSV-like aggregate output:

```text
candidate,runs,passed,errors,p50_ms,p95_ms
openrouter:openai/gpt-5.6-luna,310,226,1,662.7,1100.7
```

With `--failure-breakdown`, the command appends aggregate failure-code counts:

```text
candidate,sample_index,failure,runs
openrouter:openai/gpt-5.6-luna,16,sentence-structure,10
```

With `--category-breakdown`, it also appends category-level aggregate rows:

```text
candidate,category,runs,passed,errors,p50_ms,p95_ms
openrouter:openai/gpt-5.6-luna,punctuation-structure,50,10,0,695.7,1166.5
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
31 synthetic/public-style samples, grouped as:

| Category | Count |
| --- | ---: |
| `short-smoke` | 4 |
| `russian-filler` | 5 |
| `code-switching` | 6 |
| `punctuation-structure` | 5 |
| `commands-editor` | 3 |
| `inverse-text-normalization` | 4 |
| `safety-negative` | 4 |

The default benchmark does not download datasets or models at runtime.

## Providers

The benchmark accepts two provider forms:

- `openrouter:<model-id>` sends transcript text to OpenRouter with the selected
  routed model id and requires `OPENROUTER_API_KEY`.
- `passthrough` preserves the raw transcript locally and provides a latency and
  quality floor.

The curated OpenRouter shortlist currently mirrors the app menu:

- `openai/gpt-5.6-luna`
- `anthropic/claude-haiku-4.5`
- `google/gemini-3.1-flash-lite`
- `qwen/qwen3.6-flash`
- `deepseek/deepseek-v4-flash`
- `mistralai/mistral-small-2603`
- `minimax/minimax-m3`

## Latest Live Snapshot

Latest candidate benchmark, measured on 2026-07-12 with 10 repetitions over the
31-sample suite and the exact request sent by the app:

| Candidate | Runs | Passed | Errors | p50 | p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `openrouter:openai/gpt-5.6-luna` | 310 | 226 | 1 | 662.7 ms | 1100.7 ms |
| `openrouter:minimax/minimax-m3` | 310 | 208 | 0 | 1164.1 ms | 2788.2 ms |

### Full catalog baseline

Full OpenRouter catalog snapshot, measured on 2026-07-02 with 10
repetitions over the 30-sample `slovo-cleanup-v1` suite, using the exact request
the app sends (reasoning disabled via `reasoning: {effort: "none"}`).

| Candidate | Runs | Passed | Errors | p50 | p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `openrouter:anthropic/claude-haiku-4.5` | 300 | 230 | 0 | 1270.8 ms | 3408.4 ms |
| `openrouter:deepseek/deepseek-v4-flash` | 300 | 217 | 1 | 1617.0 ms | 5302.0 ms |
| `openrouter:qwen/qwen3.6-flash` | 300 | 216 | 1 | 797.3 ms | 2859.7 ms |
| `openrouter:mistralai/mistral-small-2603` | 300 | 214 | 0 | 524.8 ms | 3556.3 ms |
| `openrouter:openai/gpt-5.4-nano` | 300 | 209 | 0 | 824.0 ms | 2550.8 ms |
| `openrouter:google/gemini-3.1-flash-lite` | 300 | 207 | 0 | 786.3 ms | 3132.0 ms |
| `passthrough:none` | 300 | 0 | 0 | 0.0 ms | 0.0 ms |

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
| `openai/gpt-5.6-luna` (default) | 1.00 / 6.00 | 27 | n/a | 192.1 t/s | 0.70 s |
| `anthropic/claude-haiku-4.5` | 1.00 / 5.00 | 24 | n/a | 92.4 t/s | 0.93 s |
| `google/gemini-3.1-flash-lite` | 0.25 / 1.50 | 25 | 81.6% | 294 t/s | 5.2 s |
| `qwen/qwen3.6-flash` | 0.19 / 1.13 | n/a | n/a | n/a | n/a |
| `deepseek/deepseek-v4-flash` | 0.09 / 0.18 | n/a | 89.7% | 105 t/s | n/a |
| `mistralai/mistral-small-2603` | 0.15 / 0.60 | 20 | 66.8% | 173 t/s | 0.81 s |
| `minimax/minimax-m3` | 0.30 / 1.20 | n/a | n/a | n/a | n/a |

`n/a` means the model is absent from that public leaderboard as of the retrieval
date. Public multilingual leaderboards (Global-MMLU-Lite, MMMLU) do not cover
Russian, so Russian-specific quality is not represented by any number above; the
`slovo-cleanup-v1` suite is the project's own measurement on dictation-style
samples.

## Sources

- OpenRouter API docs: https://openrouter.ai/docs
- OpenRouter Chat Completions API: https://openrouter.ai/docs/api-reference/chat-completion
- OpenRouter model list API: https://openrouter.ai/api/v1/models

## Verification

PASS — updated on 2026-07-12 against Slovo's OpenRouter-only cleanup path and a
live 10-repetition OpenRouter benchmark.
