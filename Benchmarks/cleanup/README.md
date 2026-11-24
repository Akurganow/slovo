# Slovo Cleanup Benchmark Suite

`slovo-cleanup-v1.json` is the pinned default dataset for the non-product cleanup
benchmark. It is intentionally small enough to review by hand and large enough
to catch prompt overfitting that passed the original three-sample smoke suite.

The suite uses synthetic/public-style dictation text. It must not contain private
user transcripts, API keys, provider response bodies, or personal vocabulary.

## Taxonomy

| Category | Count | Purpose |
| --- | ---: | --- |
| `short-smoke` | 5 | Short utterances, repetitions, numbers, minimal dictation |
| `russian-filler` | 6 | Russian discourse fillers, false starts, self-corrections, casual speech cleanup |
| `code-switching` | 10 | Russian base with English developer/product terms, reverse embedding, conventional acronym casing (plain phrases stay lowercase) |
| `punctuation-structure` | 12 | Long dictated streams: sequential thoughts split into sentences, grammatically connected long sentences kept whole |
| `commands-editor` | 4 | Action-like editor and system commands; dictated edit commands stay content, never applied |
| `inverse-text-normalization` | 7 | Time, percent, version, and date normalization with values unchanged; idiomatic number phrases stay words |
| `safety-negative` | 8 | No chat wrapper, no unsolicited translation, no invented closing pleasantries, preserve dictated text (quoted corrections, genuine alternatives, injection-style text cleaned as content) |
| `instruction-shaped-transcript` | 3 | Permanent tripwire for the executed-dictation failure class: long task-shaped dictations that an assistant would answer instead of clean |

Total: **55 samples**, 11 of them clean cases: the reference equals the raw text
up to the first capital and the final mark. A full run is samples × repetitions,
so "550 runs" = 55 × 10.

Each sample is `id`, `category`, `raw` and a required `reference`: the expected
cleanup. Other keys are ignored.

## What a pass means

Each output is scored against its sample's reference, never against the dirty
dictation. Three coefficients, each from 0 to 1:

- **fuzzy:** how close the words are, in any order;
- **embedding:** how close the meaning is as a vector;
- **Jev:** five yes/no judgments made from the dictation, the reference and the
  output; the coefficient is the lowest of the five.

Word order, word form, casing, inner punctuation and the final mark are never
checked. The only check on the text itself is that the output is not empty.

A baseline entry is a model's recorded slack against the shared references.
Slack is 1 minus the coefficient. Every model scores against the same
references: an entry is never a separate expected result for that model.

- `baseline.json` holds one entry per candidate name (`provider:model`). Per
  sample and coefficient an entry holds the mean slack and the spread (largest
  minus smallest) across the repetitions, plus the judge's model ids, the Jev
  snapshots that answered, and the SHA-256 of the dataset file.
- A run on a sample is within a model's recorded slack when, for each
  coefficient, its slack is at most the entry's mean plus the larger of the
  entry's spread and the coefficient's floor (Jev 0.15, embedding 0.02, fuzzy
  0.05, in `judge.json`).
- A candidate passes when its share of runs within slack is at least the
  baseline's own share less 5 points, overall and in every category. The
  baseline's own runs are always within its slack, so its share is 100%.
- A candidate is judged against its own entry. A candidate with no entry (a new
  model, a local one) is judged against the entry named by
  `--baseline-candidate`, by default `openrouter:` plus the app's default cleanup
  model.
- A release fails when any catalog model gets worse than its own recorded slack.

An output that changes nothing passes on a clean case and is judged like any
other output on a messy one.

## Running the judge

| Flag | Effect |
| --- | --- |
| none of the below | Fuzzy only. No verdict. No request leaves the Mac except the candidates' own. |
| `--judge` | Adds the embedding and Jev coefficients. Needs `OPENROUTER_API_KEY`, from the environment or `--env-file`. |
| `--baseline PATH` | Applies the bar (needs `--judge`). Every candidate needs an entry, its own or the fallback's, recorded on this dataset file. |
| `--baseline-candidate ID` | The fallback entry for a candidate with none. |
| `--write-baseline PATH` | Writes the entries of the candidates that ran and leaves every other entry as it is (needs `--judge`). Refused when any run is unscored. |
| `--outputs-file PATH` | Opt-in, local. One JSON line per run: sample index and repetition (both from 1), candidate, output (`null` after a provider error), the three coefficients, each Jev question's repeats, judge errors. |

`--providers catalog --judge --baseline PATH` judges every catalog model in one
run, each against its own entry.

Exit code: `0` when no run failed and every judged candidate passes the bar, or
when no `--baseline` was given and no run failed; `2` when a run failed
(provider error, empty output, judge error), a candidate failed the bar, or a
file could not be written; `64` when the arguments or files are unusable, before
any request is sent. The command asks for nothing interactively, so a CI step
can call it.

`judge.json` holds the judge's settings: the Jev model and its five questions,
the repeats (3), the embedding model with its prefix and provider-routing
object, and the bar's floors and allowance. `embedding.provider.order` is empty
until a calibration run records the provider that served the embeddings.

### What `--judge` sends to OpenRouter

Synthetic sample text and the candidate's output, nothing else:

- `POST https://openrouter.ai/api/alpha/decisions` (Jev): the sample's raw
  text, its reference and the output, once per repeat.
- `POST https://openrouter.ai/api/v1/embeddings`: the reference and the output.

No audio and no personal vocabulary are involved. The candidate's own request is
unchanged.

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
- no reference text;
- no API keys;
- no provider response bodies;
- no caller-provided sample ids.

Per candidate the report prints runs, failed runs, latency percentiles and the
mean of each coefficient. With `--baseline` it adds one row per candidate and
per category: runs, within-slack share, the means, and `pass` or `fail`. A
candidate passes when every one of its rows does. Use `--failure-breakdown` and
`--category-breakdown` to inspect failures by sample index, failure code, and
category without exposing payload text. Only `--outputs-file` writes output text.
