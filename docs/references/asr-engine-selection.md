# ASR Engine Selection — Research & Decision Record

Date: 2026-07-01
Status: Research complete (multi-agent, adversarially verified). Decision pending
on-device acceptance test. NOT yet committed to code.

Cycle 1 (code): restores WhisperKit turbo ("large-v3-v20240930_turbo_632MB") as the
incumbent, user-proven runtime baseline behind the streaming `Transcriber` seam. Full
large-v3 remains the acceptance-gated candidate per the on-device protocol below, not
yet the shipped default.

## Why this exists

slovo needs an ASR engine. An earlier in-progress migration swapped the shipped
engine (WhisperKit / Whisper large-v3) for Apple's Speech framework
(`SpeechAnalyzer` / `DictationTranscriber`) **without** proving the swap was
necessary or that Apple Speech was the best fit. This record is the missing
preparation: the full requirement set, an exhaustive engine survey, and an
evidence-based, adversarially-verified recommendation.

## Requirements

Hard (failing either disqualifies a candidate):

1. **Code-switching** — must transcribe mixed Russian+English **within a single
   utterance** (RU+EN intra-utterance code-switching), each word in the correct
   script. Not "supports both languages when you pick one."
2. **Quality** — recognition accuracy at least as good as Whisper large-v3
   (multilingual) on Russian and on English. large-v3 is the floor and the
   code-switch reference.

Strong goal:

3. **Low latency** — transcript ready at key-up. "Live" = low latency, not a
   visible running transcript. Met by either true streaming during the hold, or a
   batch decode fast enough (~<300 ms for a few-second clip).

Constraints: fully on-device / local (no cloud ASR), macOS Apple Silicon,
Swift-callable, reasonable model size.

## The decisive finding

**Code-switching is the gate, and it disqualifies nearly every candidate.** Across
42 candidates, essentially all are refuted or must-test on RU+EN intra-utterance
code-switching. The choice therefore reduces to: *which engine is the strongest
code-switch prospect while still clearing the Whisper-large-v3 quality floor.*

Code-switching is **unverified for every candidate on slovo's actual target path**,
so the decision must be validated by an **on-device acceptance test**, not by
published benchmarks.

## Ranked candidates (top of a 42-engine survey)

| # | Engine | Code-switch | Quality vs large-v3 | Latency at key-up | On-device / Swift |
|---|--------|-------------|---------------------|-------------------|-------------------|
| 1 | **Whisper large-v3 FULL via WhisperKit (CoreML/ANE)** | **likely** — only candidate with positive RU+EN evidence (SwitchLingua best-in-class ~3×); emits mixed Cyrillic+Latin but imperfectly | **Is the floor** (RU & EN) | ~1–2 s (batch ~2.2 s; streaming ~1.7 s) | Yes — mature native Swift SDK, ANE, ~1.5 GB |
| 2 | **Qwen3-ASR-1.7B via MLX-Swift** (hedge) | must-test — negative prior (single-script collapse on ZH+EN, Hinglish); but LLM decoder + glossary biasing to attempt it | **Exceeds** floor monolingual RU & EN | ~0.4–1.3 s (batch-only) | Yes — MLX (Metal), early-stage Swift ports, ~2–4 GB |
| 3 | Whisper large-v3-**turbo** | must-test — pruned decoder degrades exactly where code-switch lives | **At risk of BELOW floor** on RU | ~1 s | Yes — same path |
| 4 | Voxtral Mini 4B Realtime (MLX) | no — documented language collapse | ~near floor, unproven mixed | ~0.48 s streaming | Yes — heavy 4B |
| 5 | Parakeet TDT 0.6B v3 (FluidAudio) | **no** — NVIDIA-confirmed "not tuned for code-switch"; half-RU/EN → all-English | at/above floor monolingual | **~0.2–0.5 s (best)** | Yes — first-class Swift SDK, ANE |
| 6 | Nemotron-3.5-ASR streaming multilingual | no — per-utterance single-language LID | ~near floor monolingual RU | excellent streaming | Yes — sherpa-onnx / CoreML |
| 7 | **Apple SpeechAnalyzer / SpeechTranscriber** | **no** — single-Locale by construction; no multi-language / auto / code-switch API | ~floor per-language (RU vs large-v3 unverified) | **best** (native streaming) | Yes — first-party, zero deps |
| 8 | Russian-only (GigaAM-v3/v2, T-one, Vosk-RU) | no — **Cyrillic-only vocabulary**, cannot emit Latin | superb RU, **no EN** | good | Yes — sherpa-onnx |
| 9 | English-only / no-Russian family (Parakeet v2/EOU, Moonshine, Kyutai, MMS, Phi-4, SeamlessM4T, Distil-Whisper) | no — no Russian and/or single-language design | fails RU half | varies | varies |
| 10 | Build-your-own RU+EN code-switch Zipformer → sherpa-onnx | must-test — no RU+EN training corpus exists | unknown | excellent if built | yes (runtime) — very high cost |

Notable consequences:

- **Apple Speech is disqualified** (rank 7): single-locale by construction, cannot
  emit correct per-word RU+EN script. This confirms the in-progress migration was a
  regression, not just a bug — abandon it.
- **The fastest engines fail the gate.** Parakeet v3 (rank 5, ~0.2–0.5 s) and Apple
  Speech (rank 7) have the best latency but cannot code-switch. Speed is moot when
  the hard requirement fails.
- **Turbo ≠ full.** The shipped config used large-v3 **turbo** (632 MB); turbo is a
  latency fallback only and risks dropping Russian below the floor. Production RU+EN
  needs **full large-v3**.

## Recommendation

**Adopt Whisper large-v3 (FULL, not turbo) on-device via WhisperKit (CoreML/ANE),
gated by a mandatory on-device RU+EN code-switch acceptance test before commit.**
It is the only engine that both meets the quality floor by definition and has real
positive RU+EN code-switch evidence. Its weaknesses — ~1–2 s latency and imperfect
per-word script fidelity — are acceptable to test against (latency is a goal, not a
hard requirement).

**Runner-up / hedge: Qwen3-ASR-1.7B via MLX-Swift.** Best monolingual quality of any
candidate and an LLM decoder with glossary/hotword biasing to attempt script
control; but its code-switch prior is negative. Test it if Whisper-full's script
fidelity or latency proves unacceptable.

**Design lever:** slovo already runs an OpenRouter text-cleanup stage after ASR.
That stage can post-correct residual transliteration / script errors (e.g.
re-Latinize a garbled English tech term), which materially relaxes the raw-ASR
code-switch bar. Design the cleanup prompt to do this and grade code-switch pass/fail
*after* cleanup, not only on raw ASR.

## Must-test on-device (before committing)

1. **Test set:** 40–60 real push-to-talk clips (2–8 s), recorded on the target Macs
   (macOS 26) through slovo's actual mic-capture path, in three buckets:
   (A) dictation-realistic — a Russian sentence with 1–3 embedded English tech terms
   (e.g. "Закоммить фичу в main branch и открой pull request"); (B) heavier balanced
   code-switch; (C) monolingual RU and monolingual EN controls.
2. **Engines:** WhisperKit full large-v3 (try decode configs: language=auto/None,
   forced ru, no-prefill/empty-prompt); Qwen3-ASR-1.7B MLX with and without an
   injected RU+EN tech glossary; optionally large-v3-turbo for latency comparison.
   Keep models pre-warmed (steady-state, not cold start).
3. **Measure per clip:** per-word script correctness (English terms in Latin, Russian
   in Cyrillic); whole-utterance language-collapse rate; failure-mode tally
   (EN→Cyrillic transliteration, translate-instead-of-transcribe, drops,
   hallucination); CER/WER on mixed vs monolingual controls; key-up→final-text latency
   (warm, ANE), on the **weakest** target chip (e.g. M1), not just a high-end Mac.
4. **Code-switch bar:** PASS if ≥90% of embedded English terms are correct-script,
   zero whole-utterance collapses on bucket A, and mixed CER ≤ ~1.5× the monolingual
   control. Grade again **after** the OpenRouter cleanup stage — an 80–90% raw score
   may still pass end-to-end if cleanup reliably repairs residual script errors.
5. **Quality bar:** monolingual RU and EN WER no worse than WhisperKit full large-v3
   on the control clips.
6. **Latency bar (goal):** ideally ≤300 ms at key-up, acceptable up to ~1 s; record
   whether full large-v3's ~1–2 s is tolerable or forces a turbo-draft +
   large-v3-finalize streaming design.

## Open questions

- Does WhisperKit's on-device path (chunk-level LID + single language-token prefill
  per 30 s window + CoreML/ANE conversion) preserve the RU+EN code-switch quality that
  SwitchLingua measured on **base** HF/PyTorch Whisper? The positive benchmark was NOT
  run on WhisperKit — the single biggest unknown.
- Which decode config maximizes per-word script fidelity (auto-detect vs forced ru vs
  no-prefill)? Whisper is highly sensitive to the language-token prefill.
- Can the OpenRouter cleanup stage reliably re-Latinize transliterated English tech
  terms without corrupting correct Russian? If yes, the raw-ASR bar relaxes and
  Whisper-full becomes a much safer pick.
- Is ~1–2 s key-up latency acceptable for push-to-talk, or a dealbreaker that forces a
  streaming hybrid or the Qwen3 hedge?
- Can Qwen3-ASR-1.7B's context/hotword biasing prevent single-script collapse for
  RU+EN? Determines whether the hedge is viable.
- Deployment hardware floor (M1 vs M4+, 8 GB vs 16 GB)? Feasibility/latency of the
  heavier models depends on it.

## Method

Multi-agent workflow (`asr-engine-research`), 84 agents, ~4.0 M tokens: 7 parallel
research finders (by engine family + cross-cutting code-switching-SoTA and latency
angles) → dedup → per-candidate adversarial verification with two skeptic lenses
(code-switching, latency/on-device; default "refuted" unless corroborated evidence)
→ ranked synthesis. Primary sources preferred (Apple docs/WWDC, HF model cards,
arXiv/Interspeech papers, GitHub issues). Full raw output archived in the workflow
transcript for this session.
