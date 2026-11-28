# Slovo Cleanup Benchmark Suite

`slovo-cleanup-v1.json` is the pinned default dataset for the non-product cleanup
benchmark. It is intentionally small enough to review by hand and large enough
to catch prompt overfitting that passed the original three-sample smoke suite.

The suite uses synthetic/public-style dictation text. It must not contain private
user transcripts, API keys, provider response bodies, or personal vocabulary.

## Taxonomy

| Category | Count | Purpose |
| --- | ---: | --- |
| `short-smoke` | 20 | Short utterances, repetitions, numbers, minimal dictation |
| `russian-filler` | 18 | Russian discourse fillers, false starts, self-corrections, casual speech cleanup |
| `code-switching` | 13 | Russian base with English developer and product terms and reverse embedding: every term survives cleanup with its meaning, in either script |
| `punctuation-structure` | 18 | Long dictated streams of sequential thoughts or one connected sentence: cleanup keeps every thought; independent statements and steps split, a clause joined by a connecting word stays in its sentence |
| `commands-editor` | 4 | Action-like editor and system commands; dictated edit commands stay content, never applied |
| `inverse-text-normalization` | 11 | Times, percents, versions and dates: each value survives cleanup unchanged; an idiomatic number phrase keeps its sense |
| `safety-negative` | 8 | No chat wrapper, no unsolicited translation, no invented closing pleasantries, preserve dictated text (quoted corrections, genuine alternatives, injection-style text cleaned as content) |
| `instruction-shaped-transcript` | 3 | Permanent tripwire for the executed-dictation failure class: long task-shaped dictations that an assistant would answer instead of clean |
| `languages` | 40 | Plain dictation in uk, de, es, fr, pt, zh, ja, ko, hi and ar, four samples each: a filler with a self-correction, a long run-on, a time and a percentage, and at least one clean case |
| `mixed-languages` | 15 | Speech mixing two languages in one utterance: de+en, es+en, zh+en, hi+en and uk+ru, three samples each |
| `translation` | 36 | The translate hold: speech in one language, cleaned and translated into the target; the reference is in the target language |
| `vocabulary` | 4 | A vocabulary sent with the dictation: a misheard listed term is repaired to its listed spelling, and an everyday word that matches a term keeps its everyday form |
| `hints` | 8 | On-device hints sent with the dictation, right or planted wrong: a keyboard language, a spell guess or a grammar finding; the reference is the cleanup no hint changes |

Total: **198 samples**, 55 of them clean cases: the raw text equals its first
reference. A full run is samples × repetitions, so "990 runs" = 198 × 5.

Each sample is `id`, `category`, `raw` and `references`, a non-empty list. The first
reference is the expected cleanup. The others are equally valid forms of it: the
other script of an English term (`main` for `мейн`, `пиар` for `PR`). Where the raw writes an English term in Cyrillic, another reference holds its
Latin form. Where it writes one in Latin and the recognizer, run on the sample's
spoken text, rendered it in Cyrillic, another reference holds that rendering. A
misheard word is not a rendering. Either script is accepted.

Two optional keys carry the language:

- `language`: the spoken language, a code of the app's recognition catalogue, or
  two codes joined by `+` for mixed speech (`uk`, `de+en`). A `languages` sample
  has one code and a `mixed-languages` sample two. A `translation` sample may
  carry it, as its source. No other category takes it.
- `translateTo`: one catalogue code. A sample with it runs as the app's translate
  hold: the cleanup request is made with the translate flag on and the code as
  the target, and the judge asks the translation questions below. Exactly the
  `translation` samples carry it.

The loader refuses a code the catalogue does not offer and a category that
disagrees with these keys. `spoken` and `voice`, kept on the samples added for
the languages, and any other key are ignored.

Two more optional keys make the cleanup call carry what the app sends for a dictation
with a vocabulary or with on-device hints. A sample without them is called with an
empty vocabulary and no hints. Every category takes them, and a `translation` sample
that carries them keeps its category:

- `vocabulary`: a list of `{"term": "QRV", "expansion": "Quick Review"}`, `expansion`
  optional. Each entry reaches the prompt as a row the user added by hand: weight 3 and
  language `en`, as `VocabularyQuickAdd` and the personalization source give it. A
  `term` that is empty or only whitespace is refused.
- `hints`: an object with any of `inputLocale` (`"en"`), `spell` (a list of
  `{"token": "Kubrix", "guesses": ["Kubrick"]}`) and `grammar` (a list of
  `{"fragment": "me and him", "message": "…", "corrections": ["he and I"]}`), where
  `guesses` and `corrections` are optional. These are the checker findings the app
  gathers at key-up. An object with no member, or a `spell` or `grammar` list written
  empty, is refused. A `spell` token must occur in the sample's `raw`, as the checker
  flags only words of the transcript.

Every term and every hint is invented, never taken from a person's vocabulary or
dictation. The categories `vocabulary` and `hints` are for plain samples whose point is
the vocabulary or the hints: a `vocabulary` sample must carry a non-empty `vocabulary`,
and a `hints` sample must carry `hints`.

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

### Samples in other languages

A sample of `languages`, `mixed-languages` or `translation` is made so:

1. Write the spoken text, as words, with no punctuation.
2. Synthesise it with one macOS `say` voice: Lesya for uk, Anna for de, Mónica for
   es, Thomas for fr, Luciana for pt, Tingting for zh, Kyoko for ja, Yuna for ko,
   Lekha for hi, Majed for ar, Samantha for en, Milena for ru. A mixed sample uses
   the voice of its first language.
3. Transcribe it once through the app's live session path and model, as above, with
   the decoding the app uses: language `.auto`, no bias terms, audio in 100 ms
   chunks at real-time pace, then `finish()`.
4. The recognizer's output is the `raw`, verbatim. A raw is never edited. If the
   recognizer garbled a content word that no cleanup could repair, rewrite the
   spoken text and transcribe again, and drop the earlier output.
5. Keep `spoken` and `voice` on the sample, so the raw can be made again.

The recognizer's form, per language:

- **Times and percentages.** Digits: `9.30` (uk, ru, de `9.30 Uhr`), `9h30` (fr,
  pt), `9点半` (zh), `9時半` (ja), `9시 반` (ko), with `%` or, in hi, `20 प्रतिशत`.
  Spanish keeps `5 y cuarto`. Arabic keeps numbers as words.
- **Punctuation.** A full-width `。` ends zh and ja sentences, and long zh and ja
  runs may have spaces between clauses instead of marks. hi and ar end with an
  ASCII `.`.
- **Script.** zh mixed with English comes back in Traditional characters, or in a
  mix of Traditional and Simplified within one sample, where plain zh is
  Simplified. A reference keeps the script of its raw, and where the raw is
  Traditional a second reference holds the Simplified form.
- **English terms.** In uk and in hi they come back in Cyrillic or Devanagari
  renderings (`полреквест`, `पुल रिक्वेस्ट`); a hi sample whose raw writes them
  in Devanagari has a second reference with the Latin form. In de and es they stay
  Latin, German taking noun hyphenation (`Pull-Request`) and capitals.
- **Fillers.** Most spoken fillers are lost or turned into another word (uk `ну`
  becomes `но`, fr `euh` becomes `et`). A raw keeps only the fillers the recognizer
  kept.

The references in these languages are written by a model and checked by a second
model. No speaker of these languages has read them, so a reference can hold a slip
that no check here would show.

## What a pass means

Each output is scored against its sample's references, never against the dirty
dictation. Three coefficients, each from 0 to 1:

- **fuzzy:** how close the words are, in any order; the best over the references;
- **embedding:** how close the meaning is as a vector; the best over the references;
- **Jev:** five yes/no judgments made from the dictation, the first reference and
  the output; the coefficient is the lowest of the five. A `translation` sample
  is asked its own five (`translationQuestions` in `judge.json`): the plain ones
  would fail a correct translation, so `same_language` becomes `in_target_language`,
  asked against the target language's name, and the other four allow translation.
  `plain_text` and the other questions that both sets share appear in both, so an
  edit to one is made in both.

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
- A candidate passes when, overall, in every category and in every language, the
  samples not within slack number at most the allowance's share of the row's
  samples (`judge.json`), and never fewer than one. A row of a few samples
  therefore tolerates one miss, and a language of four samples fails on two.
  A language row holds the samples of that `language` in `languages` and
  `mixed-languages` (`uk`, `de+en`), after the category rows. `translation` has
  no row per target: a target has one or two samples, and a two-sample row fails
  only when both miss.
- The trade: the `dropWorst` largest slacks are dropped per coefficient, so
  different repetitions may fail different coefficients without failing the bar.
  The report prints, per candidate and row, `dropped_outside`, how many
  dropped repetitions were above the entry's slack plus the floor on any
  coefficient, so such failures stay visible.
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
| `--write-baseline PATH` | Writes an entry for each candidate whose runs are all complete (an output, no failure, all three coefficients) and keeps the entries of the other models of the cleanup list; any other entry, such as that of a model that left the list, is dropped (needs `--judge`). A candidate with incomplete runs gets no entry; stderr says how many runs are missing. |
| `--outputs-file PATH` | Opt-in, local, and the resume record (below). |

`--providers catalog --judge --baseline PATH` judges every catalog model in one
run, each against its own entry.

The outputs file is append-only JSON Lines, written in the order runs finish. A line is
added when a run's cleanup finishes and again when it is judged: sample index and id (from 1), candidate,
repetition (from 1), output (`null` after a provider error), duration, the cost of the
cleanup call (`null` after a provider error or when the reply named none; a line written
before the key existed has none), the three coefficients, each Jev question's repeats, the models that answered, the failure
codes, the writing style, the SHA-256 of the ids, raws and `translateTo` targets of
the dataset, the SHA-256 of the cleanup prompts (the system message sent for the
style, with no vocabulary and no hints, one translate message per target in the
dataset, and the id and whole system message of each sample that carries a vocabulary or hints), the SHA-256 of what scored the line (the judge's settings
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
- A file written for other ids, raws, translation targets, vocabularies or hints, under another cleanup prompt or by another `--style`, is refused.
- A line scored under other judge settings keeps its output and is judged again.
  A line whose references changed but not the first keeps its Jev score, because
  Jev reads only the dictation, the first reference and the output: only the
  embedding is asked again. A line without the Jev digest is judged again whole.
  The fuzzy score is always computed again from the output.

A line cut short by a killed process is dropped, and its run is done again.

The exit code says what a CI step should do:

- 0: no run failed (no failure code), every file was written, and every
  candidate passed the bar against its own baseline entry. A candidate that
  failed only against the `--baseline-candidate` fallback entry does not change
  the code.
- 2: a run failed, or a file could not be written. A bar can pass while a dropped
  repetition failed, and the exit is then 2. This wins over 3.
- 3: a candidate failed the bar against its own baseline entry and nothing else
  failed.
- 4: a baseline entry was recorded on another dataset, judge, scheme or style.
  The command stops before any request.
- 64: the arguments or files are unusable in any other way (no key, no baseline
  entry, an unreadable file). The command stops before any request.

While it runs, the command writes progress lines to standard error, each starting with
`progress: `, as the events happen: the cleanup calls start (candidates, samples,
repetitions, calls to make, runs kept from the outputs file), each candidate's first and
last call made by this process, each repetition in which it made a call, the end of the
cleanup, the judge's start and end with one start and end per candidate, and the baseline
write. A line holds names and counts only. Calls start by repetition, then sample, then
candidate, several run at once, and the lines follow the order calls finish, so lines of
different candidates and repetitions interleave. Standard output stays the report.

A cleanup call that the provider rate-limits waits as long as the reply asks, or backs off
when the reply names no wait, and is tried again a few times before it counts as a provider error. The finish lines
count those retries and the calls that gave up after them.

The command asks for nothing interactively, so a CI step can call it. After a
release that changes a file able to change cleanup output,
`.github/workflows/cleanup-benchmark.yml` runs it over the catalogue;
`docs/release-ci.md` says what the run commits, uploads and reports.

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

The sample text (the dataset's synthetic samples, or the file `--samples` names) and
the candidate's output, nothing else:

- `POST https://openrouter.ai/api/alpha/decisions` (Jev): the sample's raw
  text, its first reference and the output, once per repeat. A translation sample
  adds the display name of its target language.
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

Per candidate the report prints runs, failed runs, latency (`p50_ms`, `p95_ms`
and `max_ms`, the slowest run, over the runs without a provider error), the
mean of each coefficient and `cost_usd`. With `--baseline` it adds one row per candidate,
per category and per language (the rows of "What a pass means"): samples, misses,
allowed misses, dropped repetitions outside the baseline's slack, the means, and
`pass` or `fail`. A
candidate passes when every one of its rows does. `cost_usd` sums the `usage.cost` that OpenRouter returned for the row's cleanup calls
(OpenRouter documentation, "Usage Accounting", Cost Breakdown:
<https://openrouter.ai/docs/guides/guides/usage-accounting.md>; no published revision;
it calls the field "The total amount charged to your account", in credits). It covers
every run of the row, those kept from an outputs file included, and is empty when no
run has a cost. A run without one (a failed call, or a run kept from a file written
before the cost was stored) adds nothing, so the sum of such a row is partial. A call
that was billed but failed is not counted, and warmup calls never are. `passthrough` makes no request, so its cost is `0.000000`. The judge's
`judge_cost_usd` stays apart: it covers the judge's requests made by this process only.
Use `--failure-breakdown` and
`--category-breakdown` to inspect failures by sample index, failure code, and
category without exposing payload text. The `category` column of both tables also
holds a language code in the rows that follow the categories.
Only `--outputs-file` writes output text.
