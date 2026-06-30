# FluidAudio + Parakeet TDT v3 (candidate ASR)

> Reference for loqui (native Swift macOS, Apple Silicon). Verified against the
> official FluidAudio repository (source code at the `v0.15.4` tag) and the
> Parakeet CoreML model card on 2026-06-27. Pinned to FluidAudio **v0.15.4**
> (latest release, published 2026-06-16). Symbols that could not be confirmed
> from canonical sources are tagged `[UNVERIFIED]`.
>
> **IMPORTANT — docs vs. source drift:** FluidAudio's own
> `Documentation/ASR/GettingStarted.md` is partly stale relative to the shipped
> source. The signatures below were confirmed against the actual Swift source at
> the `v0.15.4` tag (`Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT/`), which
> is authoritative. Where the docs and source disagree, the source wins.

## Purpose

FluidAudio is an MIT-licensed Swift SDK from Fluid Inference for fully local,
low-latency audio AI on Apple devices (speech-to-text, text-to-speech, voice
activity detection, speaker diarization). Inference is offloaded to the Apple
Neural Engine (ANE) via CoreML, which lowers memory use and is generally faster
than CPU/GPU paths.

For loqui, the relevant capability is batch ASR using NVIDIA **Parakeet TDT
0.6B v3**, converted to CoreML and distributed as
`FluidInference/parakeet-tdt-0.6b-v3-coreml`. This is the fastest local engine
in FluidAudio's own benchmarks (~110x real-time on M4 Pro for batch ASR) and
covers 25 European languages — including Russian (`ru`), which loqui requires.

> **Code-switching caveat (read before relying on this for RU+EN):** "multilingual"
> here means the single model can transcribe any one of 25 European languages — it
> does **not** claim intra-utterance RU+EN code-switching. Neither the model card
> nor the SDK documents mixed-language / mixed-script transcription within one
> utterance. In fact FluidAudio ships a `TokenLanguageFilter` whose stated purpose
> is to *suppress* wrong-alphabet tokens (e.g. it rejects emitting Cyrillic tokens
> while transcribing a Latin-script language, issue #512). The optional
> `language:` parameter on `transcribe` **forces/filters to a single language**;
> omitting it disables filtering but does not document automatic per-token language
> switching. Treat reliable intra-utterance RU+EN code-switching as
> **`[UNVERIFIED]` / not claimed** — it must be empirically tested on real
> code-switched audio before loqui depends on it. See "Model / languages notes".

## Install (SPM)

`Package.swift` (verified from the repo manifest, `swift-tools-version: 6.0`):

```swift
.package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.4")
```

Add the product to your target:

```swift
.target(
    name: "Loqui",
    dependencies: [
        .product(name: "FluidAudio", package: "FluidAudio")
    ]
)
```

Verified facts:

- Package URL: `https://github.com/FluidInference/FluidAudio.git`
- Library product: `FluidAudio`
- Also ships an executable product `fluidaudiocli` (CLI for testing/benchmarks).
- Platform minimums (from `Package.swift`): **macOS 14**, **iOS 17**.
- Swift tools version: **6.0**.
- No external SPM dependencies are declared; internal targets only
  (`FastClusterWrapper`, `MachTaskSelfWrapper`).

## Load model + transcribe (Float samples)

The model weights are not bundled — `AsrModels.downloadAndLoad(...)` fetches the
CoreML model from Hugging Face on first use and caches it locally. Pass
`version: .v3` for the multilingual Parakeet TDT v3 build (the `.v2` build is
English-only with better recall).

```swift
import FluidAudio

// 1. Download (first run) + load the Parakeet TDT v3 CoreML model.
//    version defaults to .v3 already; encoderPrecision defaults to .int8.
let models = try await AsrModels.downloadAndLoad(version: .v3)

// 2. Create the manager and load the models. (loadModels is the canonical
//    method shown in the repo README; there is NO `configure(models:)` in the
//    shipped source — see note below.)
let asrManager = AsrManager(config: .default)
try await asrManager.loadModels(models)

// 3a. Transcribe raw 16 kHz mono Float32 samples (convenience overload that
//     manages decoder state for you).
let result = try await asrManager.transcribe(samples)

// 3b. Transcribe from a file URL.
let audioURL = URL(fileURLWithPath: "/path/to/audio.wav")
let fileResult = try await asrManager.transcribe(audioURL)

// 3c. Transcribe an AVAudioPCMBuffer.
// let bufResult = try await asrManager.transcribe(audioBuffer)

print(result.text)        // transcribed text
print(result.confidence)  // confidence score (Float)
```

Verified API surface (confirmed against the Swift **source** at the `v0.15.4`
tag, `Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT/AsrManager.swift` and
`AsrModels.swift`):

- `import FluidAudio`
- `AsrModels.downloadAndLoad(to:configuration:version:encoderPrecision:encoderComputeUnits:progressHandler:)`
  — full static signature; everything has defaults. `version: AsrModelVersion`
  defaults to `.v3`; `encoderPrecision: ParakeetEncoderPrecision` defaults to
  `.int8`. The version enum is `public enum AsrModelVersion { case v2, v3,
  tdtCtc110m, tdtJa }` — i.e. **four** cases, not just `.v2`/`.v3`. (`.v3` =
  multilingual 25 languages; `.v2` = English-only.)
- `AsrManager` — the engine/manager type. Real init:
  `public init(config: ASRConfig = .default, models: AsrModels? = nil)`. Config
  type is **`ASRConfig`** (not a free-standing `Config`).
- Load models via `public func loadModels(_ models: AsrModels) async throws`.
  **`configure(models:)` does NOT exist in the source** — it appears only in the
  stale `GettingStarted.md` doc. Use `loadModels(_:)` (or pass `models:` to
  `init`).
- The full transcribe signatures in the source are:
  `transcribe(_ audioSamples: [Float], decoderState: inout TdtDecoderState, language: Language? = nil) async throws -> ASRResult`,
  plus identical overloads taking `AVAudioPCMBuffer` and `URL`, plus a
  `transcribeDiskBacked(_ url:decoderState:language:)` variant for large files.
  There are also convenience overloads (shown in the README) that take just
  `transcribe(samples)` / `transcribe(url)` / `transcribe(buffer)` and manage the
  `TdtDecoderState` internally — these are what most callers use.
- **There is no `source:` parameter** on the Parakeet TDT `transcribe` API. The
  `source: .system` form in the older docs is **not** part of this manager's
  public surface; correction below.
- The result type is **`ASRResult`** (confirmed), a `Codable, Sendable` struct
  with: `text: String`, `confidence: Float`, `duration: TimeInterval`,
  `processingTime: TimeInterval`, `tokenTimings: [TokenTiming]?`,
  `performanceMetrics: ASRPerformanceMetrics?`, `ctcDetectedTerms: [String]?`,
  `ctcAppliedTerms: [String]?`. So **word/token-level timestamps ARE available**
  via `tokenTimings` (each `TokenTiming` has `token`, `tokenId`, `startTime`,
  `endTime`, `confidence`).

### About `source:` / `AudioSource`

An `AudioSource` enum does exist
(`Sources/FluidAudio/Shared/AudioSource.swift`) but it has exactly **two** cases:
`case microphone` and `case system` (no `.file`). It is used by the streaming /
sliding-window and diarization paths to pick a processing route, **not** by the
batch Parakeet TDT `transcribe` used above. The `transcribe(samples, source:
.system)` snippet from FluidAudio's `GettingStarted.md` does not match the
shipped `AsrManager` source — do not write loqui code against it. (A
`source: AudioSource = .file` parameter does appear on a *different* manager,
the TDT-CTC-110M model in `Documentation/ASR/TDT-CTC-110M.md`, which is a
separate model from Parakeet TDT v3.)

### Audio format requirement

Parakeet expects **16 kHz mono Float32** tensors. The docs explicitly warn to
normalize input first: "Always convert with AudioConverter so differing bit
depths ... get normalized to the 16 kHz mono Float32 tensors that Parakeet
expects." FluidAudio exposes an `AudioConverter` helper for this.
`loadSamples16kMono(path:)` is **example code, not public SDK API** — it is
defined in `Documentation/Guides/AudioConversion.md` (and reused in the README /
`GettingStarted.md` snippets) as a small wrapper you copy into your own code, not
a symbol exported by the `FluidAudio` module. Do not `import` and call it
expecting it to exist; either copy that helper or use `AudioConverter` /
`AVAudioConverter` directly.

## Minimal Swift example

```swift
import AVFoundation
import FluidAudio

func transcribeFile(at path: String) async throws -> String {
    // Load multilingual Parakeet TDT v3 (downloads + caches on first run).
    let models = try await AsrModels.downloadAndLoad(version: .v3)
    let asr = AsrManager(config: .default)
    try await asr.loadModels(models)

    // 16 kHz mono Float32 expected by the model; the URL overload converts
    // the file internally. No `source:` parameter on this API.
    let url = URL(fileURLWithPath: path)
    let result = try await asr.transcribe(url)
    return result.text
}
```

## Streaming vs batch

- **Batch** is the primary mode for Parakeet TDT v3: transcribe complete audio
  files / buffers. This is the benchmarked, recommended path (~110x RTF on
  M4 Pro; the repo also cites ~190x RTF in batch in places).
- **Streaming / real-time** uses a different path. The repo documents a
  real-time model `FluidInference/parakeet-realtime-eou-120m-coreml` with
  configurable chunk sizes (160 ms lowest-latency, 320 ms, 1600 ms
  highest-throughput) and built-in silence detection with configurable debounce.
- The source at `v0.15.4` ships **several** streaming/manager types (all under
  `Sources/FluidAudio/ASR/Parakeet/`), so there is no single "streaming type
  name": `SlidingWindowAsrManager` (it **does still exist** —
  `SlidingWindow/SlidingWindowAsrManager.swift`, not removed),
  `StreamingAsrManager`, `StreamingEouAsrManager` (the realtime EOU path),
  `StreamingNemotronAsrManager` / `StreamingNemotronMultilingualAsrManager`, and
  `UnifiedAsrManager` / `StreamingUnifiedAsrManager`. Pick the one matching the
  model you load and verify its API before relying on it; the batch
  `AsrManager` above is the right entry point for loqui's record-then-transcribe
  use case.

Latency characteristics: batch ASR is throughput-oriented (tens-to-hundreds x
real-time), so for "record then transcribe" UX in loqui it is effectively
instant on Apple Silicon. For live captions you would need the realtime EOU
model, which trades model quality/coverage for low per-chunk latency.

## Model / languages notes

- **Model:** Parakeet TDT (Token Duration Transducer) 0.6B parameters, v3,
  CoreML build `FluidInference/parakeet-tdt-0.6b-v3-coreml`.
- **Compute:** runs fully on-device on the ANE/CPU on Apple Silicon. The model
  card prose describes precision as "mixed precision optimized for Core ML
  execution (ANE/CPU)". The HF repo confirms quantized encoder variants exist:
  a default fp/int8 `Encoder.mlmodelc` (~445 MB weights) and an
  `EncoderInt4.mlmodelc` (~298 MB weights) — i.e. **int4** is available.
  `AsrModels.downloadAndLoad` exposes `encoderPrecision: ParakeetEncoderPrecision`
  defaulting to **`.int8`**. The exact per-layer fp16/int8/int4 split is not
  documented; treat finer-grained quantization claims as `[UNVERIFIED]`.
- **On-disk size (measured from the HF repo file sizes, 2026-06-27):** the full
  repo is ~2.99 GB, but that includes **all** variants (v2, v3, int4 encoder,
  Japanese, CTC-110m, and duplicate `.mlpackage` sources). The active **v3** set
  loaded at runtime is roughly **~0.5–1.1 GB**: MelEncoder (~595 MB) OR Encoder
  (~445 MB, or EncoderInt4 ~298 MB) + ParakeetDecoder (~37 MB) + JointDecisionv3
  (~13 MB) + small preprocessor/melspectrogram (~1 MB) + vocab JSON (~0.2 MB).
  Plan disk cache for ~0.5–1 GB for the v3 model, not 3 GB.
- **License:** the model card **YAML frontmatter declares `license: cc-by-4.0`**
  (this is the authoritative field), while the prose body says "Apache 2.0".
  The card cites datasets `nvidia/Granary` and `nemo/asr-set-3.0`. The upstream
  base model is `nvidia/parakeet-tdt-0.6b-v3`. The FluidAudio **SDK** repo is
  MIT/Apache-2.0 (separate from the model weights' license). Resolve the
  CC-BY-4.0 vs. Apache-2.0 discrepancy before shipping; the YAML value
  (`cc-by-4.0`) is what tooling reads.
- **Languages (verified from model card YAML, 25 codes):** `en, es, fr, de, bg,
  hr, cs, da, nl, et, fi, el, hu, it, lv, lt, mt, pl, pt, ro, sk, sl, sv, ru,
  uk`. **Russian (`ru`) is confirmed present.** Ukrainian (`uk`) is also
  present. The card's prose says "25 European languages" and the YAML lists
  exactly 25 codes (counting `en`). Note: the card warns "Primary coverage is
  European languages; performance may degrade for non-European languages."
  Japanese is a *separate* model (`version: .tdtJa`), not this v3 build.
- **Multilingual ≠ code-switching (verified):** the model card calls itself
  "On-device multilingual ASR" and "Multilingual: 25 European languages", but
  there is **no claim of intra-utterance code-switching** anywhere in the card
  or SDK docs. The SDK's `TokenLanguageFilter`
  (`Documentation/ASR/TokenLanguageFilter.md`) is built to *prevent* wrong-script
  emission (it can "emit wrong-language tokens — e.g. Russian-alphabet tokens
  while transcribing Polish"), and the filter is enabled by passing `language:`
  to force a single language. For loqui's RU+EN code-switching gate this means:
  the model *can* recognize both RU and EN, but mixed RU+EN inside one utterance
  is **not a documented capability** and the language-filter machinery actively
  pushes toward a single script. Verify empirically on real code-switched audio
  (leaving `language: nil` to avoid filtering) before treating this backend as a
  code-switching solution.
- **v3 vs v2:** The v3 CoreML build **does exist** in FluidAudio and is the
  multilingual default (`version: .v3`). v2 also ships (English-only, "better
  recall"). So v3 is not v2-only — both are available.

## loqui gotchas

- **macOS 14 minimum.** FluidAudio targets macOS 14 / iOS 17. If loqui must
  support macOS 13 or earlier, this backend is out without forking.
- **First-run model download.** `downloadAndLoad` pulls the CoreML model from
  Hugging Face on first use. Plan for: network access on first launch, a
  download/progress UX (use the `progressHandler:` param), offline-failure
  handling, and disk cache (~0.5–1 GB for v3). The cache location is exposed via
  `AsrModels.defaultCacheDirectory(for: .v3)` and `downloadAndLoad(to:)` accepts
  a custom directory `URL`. Pre-bundling: not explicitly documented, but since
  you can point `to:` at any directory you control, shipping pre-downloaded model
  files inside the app bundle and loading from there is feasible — `[UNVERIFIED]`
  as an officially supported path; test it.
- **Input must be 16 kHz mono Float32.** Do not feed raw mic buffers at 44.1/48
  kHz directly — convert via FluidAudio's `AudioConverter` (or `AVAudioConverter`)
  first, or transcription quality degrades / fails.
- **Batch, not live.** Parakeet TDT v3 is batch ASR. For live captioning in
  loqui you need the separate realtime EOU model and a different code path.
- **Swift 6 / concurrency.** Package is `swift-tools-version: 6.0` and the API is
  `async`/`await` throughout (and likely actor-isolated). Ensure loqui's audio
  pipeline crosses concurrency boundaries cleanly.
- **Result type is `ASRResult`** (not `TranscriptionResult`). Word/token-level
  timestamps ARE available via `tokenTimings: [TokenTiming]?` (each `TokenTiming`
  has `token`, `tokenId`, `startTime`, `endTime`, `confidence`). Other fields:
  `duration`, `processingTime`, `performanceMetrics`, `ctcDetectedTerms`,
  `ctcAppliedTerms`. There is **no** detected-language field on `ASRResult` —
  language is an *input* (`language:` param), not an output.
- **Pin the version.** API names and docs have drifted (the shipped source
  already disagrees with `GettingStarted.md`). Pin to `0.15.4`, code against the
  **source** signatures, and re-verify symbols on upgrade.

## Full sources

- FluidAudio repository: <https://github.com/FluidInference/FluidAudio>
- ASR Getting Started:
  <https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/GettingStarted.md>
- Benchmarks:
  <https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md>
- Releases (latest v0.15.4, 2026-06-16):
  <https://github.com/FluidInference/FluidAudio/releases>
- Swift Package Index:
  <https://swiftpackageindex.com/FluidInference/FluidAudio>
- Parakeet TDT v3 CoreML model card:
  <https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml>
- Model card README (language list source):
  <https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/blob/main/README.md>
- Fluid Inference: <https://www.fluidinference.com/>

## Verification

**Date:** 2026-06-27
**Verdict:** PARTIAL (corrected) — core claims now accurate; several originally
stated API symbols were wrong and have been fixed against the shipped source.

**Method:** Independent verification (verifier did not author the doc). Confirmed
against live canonical sources: the FluidAudio repo source at the **`v0.15.4`**
tag (commit `b9d43724cbdb5a980e441fd54180964e94d470f7`), `Package.swift`, the
GitHub Releases API, the HF model-card `README.md` YAML, and the HF model repo
file-size API. Where FluidAudio's own `GettingStarted.md` disagreed with the
compiled Swift source, the **source** was treated as authoritative.

**Checked:** version & release date; `Package.swift` (tools version, platforms,
products, deps, targets); `AsrModels.downloadAndLoad` signature + `AsrModelVersion`
enum; `AsrManager` init / model-loading methods; all `transcribe` signatures;
`ASRResult` / `TokenTiming` fields; `AudioSource` enum; `loadSamples16kMono`
provenance; streaming manager type names; model-card language YAML (RU/UK);
license; quantization; on-disk size; cache directory / pre-bundling; and the
multilingual / code-switching claim.

**Corrections (before -> after):**
1. `transcribe(_:source:)` with `source: .system` -> real signature is
   `transcribe(_ samples:decoderState: inout TdtDecoderState, language: Language? = nil) -> ASRResult`
   (plus `AVAudioPCMBuffer`/`URL`/`transcribeDiskBacked` overloads and
   no-`decoderState` convenience overloads). **There is no `source:` parameter**
   on the Parakeet TDT batch API. (Source: `AsrManager.swift`.)
2. `configure(models:)` -> does not exist in source; canonical method is
   `loadModels(_:)` (or `init(config:models:)`). `configure` lives only in the
   stale doc. (Source: `AsrManager.swift`, repo `README.md`.)
3. `AudioSource` "other cases `[UNVERIFIED]`" -> enum has exactly two cases,
   `.microphone` and `.system` (no `.file`), and is not used by the TDT batch
   `transcribe`. (Source: `Shared/AudioSource.swift`.)
4. Result-type uncertainty (`ASRResult` vs `TranscriptionResult`; fields
   `[UNVERIFIED]`) -> confirmed **`ASRResult`** with full field list incl.
   `tokenTimings: [TokenTiming]?` (word/token timestamps DO exist). No
   detected-language output field. (Source: `AsrTypes.swift`.)
5. `loadSamples16kMono(path:)` "`[UNVERIFIED]` public vs example" -> confirmed
   **example code only** (`Documentation/Guides/AudioConversion.md`), not an
   exported SDK symbol.
6. `AsrModelVersion` "`.v3` or `.v2`" -> four cases: `.v2, .v3, .tdtCtc110m,
   .tdtJa`; `.v3` is the default. (Source: `AsrModels.swift`.)
7. `SlidingWindowAsrManager` "treat as `[UNVERIFIED]` / possibly removed" ->
   **it still exists** at `v0.15.4`; multiple streaming managers coexist
   (`StreamingAsrManager`, `StreamingEouAsrManager`, `UnifiedAsrManager`, etc).
8. License "Apache 2.0 (model card)" -> the YAML frontmatter declares
   `license: cc-by-4.0` (authoritative field); the prose body says Apache 2.0 —
   flagged as a model-card discrepancy.
9. On-disk size "`[UNVERIFIED]`, high-hundreds-of-MB" -> measured from HF file
   sizes: full repo ~2.99 GB (all variants), active **v3 set ~0.5–1.1 GB**.
10. Quantization "`[UNVERIFIED]`" -> `EncoderInt4.mlmodelc` exists (int4) and
    `downloadAndLoad(encoderPrecision:)` defaults to `.int8`; per-layer split
    still unspecified.
11. Cache/pre-bundle "`[UNVERIFIED]`" -> `AsrModels.defaultCacheDirectory(for:)`
    is public and `downloadAndLoad(to:)` takes a custom directory; pre-bundling
    feasible via `to:` but not officially documented.
12. Added an explicit **code-switching caveat**: multilingual ≠ intra-utterance
    RU+EN code-switching; the `TokenLanguageFilter` actively *suppresses*
    cross-script tokens.

**URLs validated (live, 2026-06-27):**
- Releases API confirmed `v0.15.4` published `2026-06-16T17:49:06Z`.
- Source at tag commit `b9d43724...`:
  `Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT/AsrManager.swift`,
  `.../AsrModels.swift`, `.../AsrTypes.swift`, `Shared/AudioSource.swift`,
  `Package.swift`.
- HF model card `README.md` YAML (25 language codes incl. `ru`, `uk`;
  `license: cc-by-4.0`; base `nvidia/parakeet-tdt-0.6b-v3`).
- HF model repo file-size API (per-artifact sizes; total 2.99 GB).
- `Documentation/ASR/TokenLanguageFilter.md` (script-filter behavior).

**Still unverifiable / open:**
- Exact int8/fp16/int4 per-layer quantization split (model card silent).
- Whether intra-utterance RU+EN code-switching actually works in practice —
  **not claimed** by any source; must be measured on real code-switched audio.
- Pre-bundling as an officially supported flow (feasible via `to:`, undocumented).
- Whether the no-`decoderState` convenience `transcribe` overloads carry the
  optional `language:` arg (the explicit `inout TdtDecoderState` overloads do;
  the convenience forms are shown without it in the README).
- The license conflict (YAML `cc-by-4.0` vs prose `Apache 2.0`) is a real
  ambiguity in the upstream card, not resolvable from the card alone.
