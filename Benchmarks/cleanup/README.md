# Slovo Cleanup Benchmark Suite

`slovo-cleanup-v1.json` is the pinned default dataset for the non-product cleanup
benchmark. It is intentionally small enough to review by hand and large enough
to catch prompt overfitting that passed the original three-sample smoke suite.

The suite uses synthetic/public-style dictation text. It must not contain private
user transcripts, API keys, provider response bodies, or personal vocabulary.

## Taxonomy

| Category | Count | Purpose |
| --- | ---: | --- |
| `short-smoke` | 4 | Short utterances, repetitions, numbers, minimal dictation |
| `russian-filler` | 6 | Russian discourse fillers, false starts, self-corrections, casual speech cleanup |
| `code-switching` | 9 | Russian base with English developer/product terms, reverse embedding, conventional acronym casing (plain phrases stay lowercase) |
| `punctuation-structure` | 12 | Long dictated streams: sequential thoughts split into sentences, grammatically connected long sentences kept whole |
| `commands-editor` | 4 | Action-like editor and system commands; dictated edit commands stay content, never applied |
| `inverse-text-normalization` | 7 | Time, percent, version, and date normalization with values unchanged; idiomatic number phrases stay words |
| `safety-negative` | 8 | No chat wrapper, no unsolicited translation, no invented closing pleasantries, preserve dictated text (quoted corrections, genuine alternatives, injection-style text cleaned as content) |

Total: **50 samples**. A full run is samples × repetitions, so "500 runs" =
50 × 10. Compare runs by PASS RATE, not raw counts.

## Upstream Research

Hugging Face resources are used as research/provenance, not as a live runtime
dependency. The benchmark reads this pinned file by default.

- Hugging Face Audio Course, ASR evaluation:
  <https://huggingface.co/learn/audio-course/en/chapter5/evaluation>
- Hugging Face Audio Course, dataset selection:
  <https://huggingface.co/learn/audio-course/en/chapter5/choosing_dataset>
- Russian spellcheck and punctuation benchmark:
  <https://huggingface.co/datasets/ai-forever/spellcheck_punctuation_benchmark>
- RuSpellGold:
  <https://huggingface.co/datasets/RussianNLP/RuSpellGold>
- Punctuation restoration dataset pattern:
  <https://huggingface.co/datasets/clarin-pl/2021-punctuation-restoration>

## Report Contract

Reports stay aggregate-only:

- no raw transcript text;
- no cleaned output text;
- no API keys;
- no provider response bodies;
- no caller-provided sample ids.

Use `--failure-breakdown` and `--category-breakdown` to inspect failures by
sample index, failure code, and category without exposing payload text.
