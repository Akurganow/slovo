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
| `code-switching` | 10 | Russian base with English developer and product terms and reverse embedding: every term survives cleanup with its meaning, in either script |
| `punctuation-structure` | 12 | Long dictated streams of sequential thoughts or one connected sentence: cleanup keeps every thought; how it splits and punctuates them is free |
| `commands-editor` | 4 | Action-like editor and system commands; dictated edit commands stay content, never applied |
| `inverse-text-normalization` | 7 | Times, percents, versions and dates: each value survives cleanup unchanged; an idiomatic number phrase keeps its sense |
| `safety-negative` | 8 | No chat wrapper, no unsolicited translation, no invented closing pleasantries, preserve dictated text (quoted corrections, genuine alternatives, injection-style text cleaned as content) |
| `instruction-shaped-transcript` | 3 | Permanent tripwire for the executed-dictation failure class: long task-shaped dictations that an assistant would answer instead of clean |

Total: **55 samples**, 21 of them clean cases: the raw text equals its first
reference. A full run is samples × repetitions, so "275 runs" = 55 × 5.

Each sample is `id`, `category`, `raw` and `references`, a non-empty list. The first
reference is the expected cleanup. The others are equally valid forms of it: the
other script of an English term (`main` for `мейн`, `пиар` for `PR`). Where the raw writes an English term in Cyrillic, another reference holds its
Latin form. Where it writes one in Latin and the recognizer, run on the sample's
spoken text, rendered it in Cyrillic, another reference holds that rendering. A
misheard word is not a rendering. Either script is accepted. Other keys
are ignored.

## The form of a raw transcript

Every `raw` is text the speech recognizer can emit: the app's WhisperKit model
(`Config.defaultAsrModel`, a Whisper large-v3 turbo build) with the decoding
options the app sets. Slovo's own steps between the decoder and the cleanup
request change only whitespace and strip `<|…|>` tokens, so the recognizer's
form reaches cleanup as it is.

- **Casing and punctuation.** Mostly sentence case with commas, full stops and
  question marks: Whisper is trained on transcripts "without any significant
  standardization" (Radford et al., "Robust Speech Recognition via Large-Scale
  Weak Supervision", arXiv 2212.04356v1, section 2.1; paper). Long run-ons come
  back joined with commas or cut by a stray full stop, with stray capitals.
  Some raws stay lower case and unpunctuated: users report large-v3 doing so
  (`openai/whisper` discussion 1762; reports). Quotation marks may be guessed.
- **Numbers.** Digits: `15%`, `12% to 9%`, `10 по 24 августа`, times as
  `9.30` and `10.45`, a spoken "ноль ноль один" as `001`.
- **Fillers.** Russian `ну`, `вот`, `короче` and `ой нет` survive; English
  `uh` and `um` mostly do not (CrisperWhisper, arXiv 2408.16589v1: "Whisper
  eliminates many filler words"; paper). A raw keeps only fillers that
  survive.
- **Spoken punctuation.** No raw depends on how a spoken "question mark" is
  written.
- **English terms in Russian speech.** Latin, often title-cased (`Settings`,
  `API Key`, `GitHub Actions`), or a Cyrillic rendering (`коммит`, `бенчмарк`,
  `хотфикс`), or a mix. A reference keeps the script the raw uses.
  Where the raw writes an English term in Cyrillic, another reference holds its
  Latin form. Where it writes one in Latin and the recognizer, run on the sample's
  spoken text, rendered it in Cyrillic, another reference holds that rendering. A
  misheard word is not a rendering. Either script is accepted.
- **Apostrophes.** ASCII `'` (`we'll`, `c'est`).

Measured: each sample's spoken text, synthesised with the macOS `say` voices
Milena (Russian) and Reed (English US) and transcribed once through the app's
live session path (WhisperKit `argmax-oss-swift` 1.1.1, revision
`1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4`; a run). A synthetic voice reads
English terms with a Russian accent, so the recognizer's misreadings of
English terms were not kept: those raws write the term as Whisper writes it
from a clear speaker.

## What a pass means

Each output is scored against its sample's references, never against the dirty
dictation. Three coefficients, each from 0 to 1:

- **fuzzy:** how close the words are, in any order; the best over the references;
- **embedding:** how close the meaning is as a vector; the best over the references;
- **Jev:** five yes/no judgments made from the dictation, the first reference and
  the output; the coefficient is the lowest of the five.

Word order, word form, casing, inner punctuation and the final mark are never
checked. The only check on the text itself is that the output is not empty.

A baseline entry is a model's recorded slack against the shared references.
Slack is 1 minus the coefficient. Every model scores against the same
references: an entry is never a separate expected result for that model.

- One scheme measures an entry and a candidate. `judge.json` sets `bar.repetitions`
  and `bar.dropWorst`. `--baseline` and `--write-baseline` use `bar.repetitions` as
  `--repetitions` when it is left out, and refuse any other explicit value before a
  request.
- Per sample and coefficient, the slack is the mean of the repetitions' slacks
  after the `dropWorst` largest are dropped. With today's values, 5 and 2, that is
  the mean of the 3 smallest of 5. A run without a score counts as slack 1.
- `baseline.json` holds one entry per candidate name (`provider:model`). Per
  sample and coefficient an entry holds that slack, plus the repetition count,
  `dropWorst` and the writing style, the response models that scored the runs, the SHA-256 of the dataset file and the
  SHA-256 of the judge's settings (the Jev and embedding sections of `judge.json`).
- A candidate's sample is within slack when, for each coefficient, its slack is at
  most the entry's on that sample plus the coefficient's floor (the floors are in
  `judge.json`).
- A candidate passes when, overall and in every category, the samples not within
  slack number at most the allowance's share of the row's samples (`judge.json`),
  and never fewer than one. A row of a few samples therefore tolerates one miss.
- The trade: the `dropWorst` largest slacks are dropped per coefficient, so
  different repetitions may fail different coefficients without failing the bar.
  The report prints, per candidate and category, `dropped_outside`, how many
  dropped repetitions were outside the entry's slack, so such failures stay visible.
- A candidate is judged against its own entry. A candidate with no entry (a new
  model, a local one) is judged against the entry named by
  `--baseline-candidate`, by default `openrouter:` plus the app's default cleanup
  model.
- `--baseline` refuses an entry recorded on another dataset file, with other
  judge settings, with other `bar.repetitions` or `bar.dropWorst`, or under another
  `--style`: rewrite it with `--write-baseline`.

An output that changes nothing passes on a clean case and is judged like any
other output on a messy one.

## Running the judge

| Flag | Effect |
| --- | --- |
| none of the below | Fuzzy only. No verdict. No request leaves the Mac except the candidates' own. |
| `--judge` | Adds the embedding and Jev coefficients. Needs `OPENROUTER_API_KEY`, from the environment or `--env-file`. Use `--providers catalog` or a named model: `passthrough`, the default list's last entry, is judged like any candidate. It fails the bar against another model's entry, and `--write-baseline` gives it an entry of its own when it is in `--providers`. |
| `--baseline PATH` | Applies the bar (needs `--judge`; `--repetitions` defaults to `bar.repetitions` in `judge.json`). Every candidate needs an entry, its own or the fallback's. |
| `--baseline-candidate ID` | The fallback entry for a candidate with none. |
| `--write-baseline PATH` | Writes an entry for each candidate whose runs are all complete (an output, no failure, all three coefficients) and leaves every other entry as it is (needs `--judge`). A candidate with incomplete runs gets no entry; stderr says how many runs are missing. |
| `--outputs-file PATH` | Opt-in, local, and the resume record (below). |

`--providers catalog --judge --baseline PATH` judges every catalog model in one
run, each against its own entry.

The outputs file is append-only JSON Lines. A line is added when a run's cleanup
finishes and again when it is judged: sample index and id (from 1), candidate,
repetition (from 1), output (`null` after a provider error), duration, the three
coefficients, each Jev question's repeats, the models that answered, the failure
codes, the writing style, the SHA-256 of the ids and raws of the dataset, the
SHA-256 of the cleanup prompt (the system message sent for the style, with no
vocabulary and no hints), the SHA-256 of what scored the line (the judge's settings
and the sample's references) and the SHA-256 of what Jev scored it under (the
judge's settings and the sample's first reference); the last two are empty without
`--judge`. It holds output text, so it stays local.
Naming an existing file resumes it, the last line of a run winning:

- A run with all three coefficients and no failure is not repeated.
- A run with an output but no full score is judged again without the cleaner.
- A provider error or a missing run is run again.
- A run whose output was empty is neither judged nor cleaned again: it is the
  candidate's failure, and no baseline entry is written while the candidate has an
  empty-output run.
- A file written for other ids or raws, under another cleanup prompt or by another `--style`, is refused.
- A line scored under other judge settings keeps its output and is judged again.
  A line whose references changed but not the first keeps its Jev score, because
  Jev reads only the dictation, the first reference and the output: only the
  embedding is asked again. A line without the Jev digest is judged again whole.
  The fuzzy score is always computed again from the output.

A line cut short by a killed process is dropped, and its run is done again.

The exit code carries the verdict, as the usage text of the command says. The
command asks for nothing interactively, so a CI step can call it. No CI job
calls it yet.

`judge.json` holds the judge's settings: the Jev model, path, repeats and
questions, the embedding model, prefix and provider-routing object, and the bar's
floors, allowance, repetitions and `dropWorst`. `embedding.provider.order` names the one provider every
embeddings request goes to, with fallbacks off, so every run scores with the same
weights.

Sources for what the settings name, all documentation: the Jev request and response
shapes are those of OpenRouter's decisions tutorial
(<https://openrouter.ai/docs/guides/community/jev-tutorial.md>; no published
revision; read 2026-11-24); the embeddings request and its `provider` field are
those of OpenRouter's embeddings reference
(<https://openrouter.ai/docs/api/api-reference/embeddings/create-embeddings.md>;
no published revision; read 2026-11-24); the instruction prefix follows the pattern
of the Qwen3-Embedding-8B model card, `Instruct: {task_description}\nQuery:{query}`, whose task text the card says to
customize
(<https://huggingface.co/Qwen/Qwen3-Embedding-8B/blob/1d8ad4ca9b3dd8059ad90a75d4983776a23d44af/README.md>,
the card at the commit of `main` read on 2026-11-24). The card puts the instruction
on the query only ("No need to add instruction for retrieval documents"); putting
it on both texts of a similarity comparison, with the task text in `judge.json`, is
the choice made here.

### What `--judge` sends to OpenRouter

Synthetic sample text and the candidate's output, nothing else:

- `POST https://openrouter.ai/api/alpha/decisions` (Jev): the sample's raw
  text, its first reference and the output, once per repeat.
- `POST https://openrouter.ai/api/v1/embeddings`: the references and the output.

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
per category: samples, misses, allowed misses, dropped repetitions outside the
baseline's slack, the means, and `pass` or `fail`. A
candidate passes when every one of its rows does. Use `--failure-breakdown` and
`--category-breakdown` to inspect failures by sample index, failure code, and
category without exposing payload text. Only `--outputs-file` writes output text.
