# Cleanup benchmark

Slovo needs cleanup candidates to be compared by latency and by product quality.
The benchmark is a non-product SwiftPM executable: it is not linked into the
menu-bar app and it does not read Keychain. The OpenRouter API key can be
supplied from process environment variables or a gitignored dotenv file.

## Command

```sh
swift run --disable-automatic-resolution slovo-cleanup-benchmark \
  --env-file .env \
  --providers openrouter:openai/gpt-5.4-nano,openrouter:anthropic/claude-haiku-4.5,openrouter:google/gemini-2.5-flash-lite,passthrough \
  --repetitions 10 \
  --failure-breakdown \
  --category-breakdown
```

The report is CSV-like aggregate output:

```text
candidate,runs,passed,errors,p50_ms,p95_ms
openrouter:openai/gpt-5.4-nano,300,211,0,787.5,3054.2
```

With `--failure-breakdown`, the command appends aggregate failure-code counts:

```text
candidate,sample_index,failure,runs
openrouter:openai/gpt-5.4-nano,3,sentence-structure,2
```

With `--category-breakdown`, it also appends category-level aggregate rows:

```text
candidate,category,runs,passed,errors,p50_ms,p95_ms
openrouter:openai/gpt-5.4-nano,punctuation-structure,50,9,0,866.0,2093.4
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
30 synthetic/public-style samples, grouped as:

| Category | Count |
| --- | ---: |
| `short-smoke` | 4 |
| `russian-filler` | 5 |
| `code-switching` | 6 |
| `punctuation-structure` | 5 |
| `commands-editor` | 3 |
| `inverse-text-normalization` | 4 |
| `safety-negative` | 3 |

The default benchmark does not download datasets or models at runtime.

## Wispr Flow Reference Bar

Wispr Flow's public feature page describes cleanup beyond raw transcription:
filler removal, punctuation, list formatting, and correction/backtracking while
the user speaks. Its release notes also expose cleanup levels from "None" through
"High", with "Light" specifically cleaning filler words and grammar.

This makes the benchmark's product bar explicit: a fast provider that leaves
spoken filler words and unstructured run-on text untouched is not good enough,
even if its latency is excellent.

Wispr's public privacy/data-control pages describe a cloud processing model with
Privacy Mode and Cloud Sync controls. Slovo should not copy that architecture:
Slovo's audio path remains local, and only already-transcribed text may leave the
Mac when cloud cleanup is enabled.

## Providers

The benchmark accepts two provider forms:

- `openrouter:<model-id>` sends transcript text to OpenRouter with the selected
  routed model id and requires `OPENROUTER_API_KEY`.
- `passthrough` preserves the raw transcript locally and provides a latency and
  quality floor.

The curated OpenRouter shortlist currently mirrors the app menu:

- `openai/gpt-5.4-nano`
- `anthropic/claude-haiku-4.5`
- `google/gemini-2.5-flash-lite`

## Sources

- Wispr Flow features: https://wisprflow.ai/features
- Wispr Flow data controls: https://wisprflow.ai/data-controls
- Wispr Flow privacy: https://wisprflow.ai/privacy
- Wispr Flow release notes: https://wisprflow.ai/whats-new
- OpenRouter API docs: https://openrouter.ai/docs
- OpenRouter Chat Completions API: https://openrouter.ai/docs/api-reference/chat-completion
- OpenRouter model list API: https://openrouter.ai/api/v1/models

## Verification

PASS — updated on 2026-07-01 against Slovo's OpenRouter-only cleanup path and a
live 10-repetition OpenRouter benchmark. Wispr internals are not public; statements
about its implementation are limited to public privacy/data-control text and
product features.
