# Cleanup benchmark

Slovo needs cleanup providers to be compared by latency and by product quality.
The benchmark is a non-product SwiftPM executable: it is not linked into the
menu-bar app and it does not read Keychain. Local API keys can be supplied from
process environment variables or a gitignored dotenv file.

## Command

```sh
swift run --disable-automatic-resolution slovo-cleanup-benchmark \
  --env-file .env \
  --providers anthropic:claude-haiku-4-5,openai:gpt-5.4-nano \
  --repetitions 10 \
  --failure-breakdown \
  --category-breakdown
```

The report is CSV-like aggregate output:

```text
candidate,runs,passed,errors,p50_ms,p95_ms
openai:gpt-5.4-nano,300,211,0,690.4,1662.1
```

With `--failure-breakdown`, the command appends aggregate failure-code counts:

```text
candidate,sample_index,failure,runs
openai:gpt-5.4-nano,3,sentence-structure,2
```

With `--category-breakdown`, it also appends category-level aggregate rows:

```text
candidate,category,runs,passed,errors,p50_ms,p95_ms
openai:gpt-5.4-nano,punctuation-structure,50,9,0,735.8,1954.5
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

Hugging Face datasets are used as upstream research/provenance only; the default
benchmark does not download datasets or models at runtime.

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

## Local Provider Candidates

Two local paths are plausible for the next implementation step:

- **Embedded MLX Swift / MLX Swift LM.** This is the best fit for a built-in
  Apple Silicon provider. Apple's MLX project is optimized for unified memory on
  Apple silicon, and the official Swift examples include LLM apps/tools that
  download models from Hugging Face and generate text locally.
- **Ollama localhost adapter.** This is easier to test because it is a local HTTP
  API with `/api/chat`, `stream: false`, and `keep_alive`, but it is not embedded
  in Slovo. It is useful as a benchmark candidate or fallback experiment, not as
  the final built-in provider.

For the first embedded model candidate, prefer a small multilingual Qwen3 model
in non-thinking mode. Qwen documents broad multilingual support, and its repo
explicitly calls out MLX support on Apple Silicon. The benchmark should decide
between `0.6B`, `1.7B`, and larger variants by observed latency and quality on
Slovo's own samples rather than by model-card claims alone.

## Sources

- Wispr Flow features: https://wisprflow.ai/features
- Wispr Flow data controls: https://wisprflow.ai/data-controls
- Wispr Flow privacy: https://wisprflow.ai/privacy
- Wispr Flow release notes: https://wisprflow.ai/whats-new
- Apple MLX overview: https://opensource.apple.com/projects/mlx
- MLX Swift: https://github.com/ml-explore/mlx-swift
- MLX Swift examples: https://github.com/ml-explore/mlx-swift-examples
- MLX Swift LM: https://github.com/ml-explore/mlx-swift-lm
- Qwen3 blog: https://qwenlm.github.io/blog/qwen3/
- Qwen3 repository: https://github.com/qwenLM/qwen3
- Ollama API: https://github.com/ollama/ollama/blob/main/docs/api.md

## Verification

PASS — verified on 2026-06-30 against public Wispr Flow pages and official
MLX/Qwen/Ollama sources. Wispr internals are not public; statements about its
implementation are limited to public privacy/data-control text and product
features. MLX integration details still require an implementation spike against
the current Swift packages before becoming product code.
