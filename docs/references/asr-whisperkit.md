# WhisperKit (on-device ASR runtime)

> Reference for **slovo** (native Swift, macOS, Apple Silicon). WhisperKit runs
> Whisper locally via CoreML on the Apple Neural Engine (ANE) / GPU / CPU. It **is**
> Slovo's shipped on-device ASR runtime (Whisper large-v3 turbo, restored in
> cycle 1).

## Status (verified 2026-06-27)

- **Latest tag:** `v1.0.0` (released 2026-05-01). Actively maintained
  (`v0.16.0` → `v0.18.0` shipped Feb–Apr 2026, then `v1.0.0` in May).
- **Repo rename:** as of `v1.0.0`, WhisperKit "graduated" into the **Argmax
  Open-Source SDK**. The Git repo is now `argmaxinc/argmax-oss-swift`; the old
  `argmaxinc/WhisperKit` URL redirects to it. The SDK bundles three products:
  `WhisperKit` (STT), `SpeakerKit` (diarization), `TTSKit` (TTS), plus an
  umbrella `ArgmaxOSS` product. Slovo links only the `WhisperKit` product; the
  other products remain reference material.
- License: MIT.

## Purpose

This document records Slovo's WhisperKit integration path. Slovo's production
runtime links WhisperKit: production dictation runs Whisper large-v3 turbo
on-device via `AudioStreamTranscriber`, fed with 16 kHz mono `[Float]` samples
from Slovo's existing microphone pipeline.

## Install (Swift Package Manager)

Package URL: `https://github.com/argmaxinc/argmax-oss-swift.git`
(the legacy `argmaxinc/WhisperKit.git` URL still resolves via redirect.)

```swift
// Package.swift
dependencies: [
    // README pins `from: "0.9.0"`; use `from: "1.0.0"` to require the Swift 6 / SDK-graduated line.
    .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "Slovo",
        dependencies: [
            .product(name: "WhisperKit", package: "argmax-oss-swift"),
        ]
    ),
]
```

```swift
import WhisperKit
```

**Minimum platforms (WhisperKit product):** macOS 14.0+, Xcode 16.0+.
(Other products differ — SpeakerKit macOS 13.0+, TTSKit macOS 15.0+ — but slovo
uses only WhisperKit, so macOS 14.0 is the floor.)

## Key API

### Init

```swift
// Loads the recommended default model (downloads on first run).
let pipe = try await WhisperKit()

// Explicit model + config.
let config = WhisperKitConfig(model: "large-v3-v20240930_626MB")
let pipe = try await WhisperKit(config)
```

`WhisperKit` is `open class WhisperKit`. Construction is `async throws` (it
resolves the model, optionally downloads, prewarms, and loads).

`WhisperKitConfig` public init (verbatim from
`Sources/WhisperKit/Core/Configurations.swift`):

```swift
public init(model: String? = nil,
            downloadBase: URL? = nil,
            modelRepo: String? = nil,
            modelToken: String? = nil,
            modelEndpoint: String? = nil,
            modelFolder: String? = nil,
            tokenizerFolder: URL? = nil,
            computeOptions: ModelComputeOptions? = nil,
            audioInputConfig: AudioInputConfig? = nil,
            audioProcessor: (any AudioProcessing)? = nil,
            featureExtractor: (any FeatureExtracting)? = nil,
            audioEncoder: (any AudioEncoding)? = nil,
            textDecoder: (any TextDecoding)? = nil,
            logitsFilters: [any LogitsFiltering]? = nil,
            segmentSeeker: (any SegmentSeeking)? = nil,
            voiceActivityDetector: VoiceActivityDetector? = nil,
            verbose: Bool = true,
            logLevel: Logging.LogLevel = .info,
            prewarm: Bool? = nil,
            load: Bool? = nil,
            download: Bool = true,
            useBackgroundDownloadSession: Bool = false)
```

Knobs slovo will care about:
- `model` — variant name (see table). `nil` ⇒ library-recommended default.
- `modelRepo` — override Hugging Face repo. The init default is `nil`; when
  unset, model resolution falls back to `"argmaxinc/whisperkit-coreml"`. Set
  only for custom/fine-tuned models.
- `modelFolder` — point at an already-downloaded model dir to skip the network
  entirely (good for bundling/offline-first).
- `computeOptions` — `ModelComputeOptions` to pin CoreML compute units (ANE/GPU/CPU).
- `download` — set `false` to forbid network fetches (fail instead of downloading).
- `prewarm` / `load` — control eager ANE compile + weight load at init.

### Transcribe (Float array — slovo's path)

Verbatim from `Sources/WhisperKit/Core/WhisperKit.swift`:

```swift
open func transcribe(
    audioArray: [Float],
    decodeOptions: DecodingOptions? = nil,
    callback: TranscriptionCallback? = nil,
    segmentCallback: SegmentDiscoveryCallback? = nil
) async throws -> [TranscriptionResult]
```

File-path variant (handy for tests / debugging):

```swift
open func transcribe(
    audioPath: String,
    decodeOptions: DecodingOptions? = nil,
    callback: TranscriptionCallback? = nil
) async throws -> [TranscriptionResult]
```

Both return **`[TranscriptionResult]`** (one element per audio clip / chunk).

### Result type

`TranscriptionResult` is a reference type. Public properties (verbatim):

```swift
@TranscriptionPropertyLock public var text: String
@TranscriptionPropertyLock public var segments: [TranscriptionSegment]
@TranscriptionPropertyLock public var language: String
@TranscriptionPropertyLock public var timings: TranscriptionTimings
@TranscriptionPropertyLock public var seekTime: Float?
```

For final tail decoding, read `result.text` and combine it with the stream's
already-confirmed segments. `TranscriptionSegment` carries per-segment
`start`/`end`/`text`/`tokens`/`avgLogprob`/`noSpeechProb` and optional
`words: [WordTiming]?` if word timestamps are enabled.

### Language & task (`DecodingOptions`)

Verbatim public init from `Configurations.swift` (selected fields):

```swift
public init(
    verbose: Bool = false,
    task: DecodingTask = .transcribe,
    language: String? = nil,
    temperature: Float = 0.0,
    temperatureIncrementOnFallback: Float = 0.2,
    temperatureFallbackCount: Int = 5,
    sampleLength: Int = Constants.maxTokenContext,
    topK: Int = 5,
    usePrefillPrompt: Bool = true,
    detectLanguage: Bool? = nil,
    skipSpecialTokens: Bool = false,
    withoutTimestamps: Bool = false,
    wordTimestamps: Bool = false,
    // ... thresholds, prompt/prefix tokens, clipTimestamps, chunkingStrategy, etc.
)
```

- **Russian:** `DecodingOptions(language: "ru")` (ISO 639-1 code).
- **Auto-detect:** leave `language: nil` and set `detectLanguage: true`.
- **Task:** `DecodingTask` is `case transcribe` / `case translate`. slovo wants
  `.transcribe` (the default). `.translate` would force English output.
- Language selection requires a **multilingual** model (the `large-v3*` variants
  are multilingual; `*.en` variants are English-only).

## Minimal Swift example (Slovo's live path)

```swift
import WhisperKit

// Build once, reuse across dictations.
let config = WhisperKitConfig(
    model: "large-v3-v20240930_626MB",
    computeOptions: ModelComputeOptions(
        audioEncoderCompute: .cpuAndNeuralEngine,
        textDecoderCompute: .cpuAndNeuralEngine
    ),
    download: true       // set false + modelFolder for a fully offline bundle
)
let whisper = try await WhisperKit(config)

let options = DecodingOptions(task: .transcribe, language: nil, detectLanguage: true)
let stream = AudioStreamTranscriber(
    audioEncoder: whisper.audioEncoder,
    featureExtractor: whisper.featureExtractor,
    segmentSeeker: whisper.segmentSeeker,
    textDecoder: whisper.textDecoder,
    tokenizer: whisper.tokenizer!,
    audioProcessor: externalAudioInput,
    decodingOptions: options,
    stateChangeCallback: handleStateChange
)

// Start at key-down. `externalAudioInput` receives each converted microphone
// chunk while the key is held; stop and finalize the unfinished tail at key-up.
try await stream.startStreamTranscription()
```

`ModelComputeOptions` public init (verbatim from `Models.swift`):

```swift
public init(
    melCompute: MLComputeUnits = .cpuAndGPU,
    audioEncoderCompute: MLComputeUnits? = nil,
    textDecoderCompute: MLComputeUnits = .cpuAndNeuralEngine
)
```

(Note: only these three fields exist — there is **no** `prefillCompute`.)

## Models

Downloaded on demand from Hugging Face:
`https://huggingface.co/argmaxinc/whisperkit-coreml` (CoreML `.mlmodelc`
packages). Cached locally after first fetch; pre-stage with `modelFolder` for
offline use.

**Naming:** on Hugging Face each model is a directory named
`openai_whisper-<name>` (e.g. `openai_whisper-large-v3-v20240930_626MB`); the
string you pass to `WhisperKitConfig(model:)` is the `<name>` suffix (e.g.
`large-v3-v20240930_626MB`). Each directory holds `AudioEncoder.mlmodelc`,
`MelSpectrogram.mlmodelc`, `TextDecoder.mlmodelc` plus `config.json` /
`generation_config.json`. (Verified against the live HF repo file listing,
2026-06-27.)

| Model name (`config.model`)     | Type           | On-disk | Notes |
|---------------------------------|----------------|---------|-------|
| `large-v3-v20240930_626MB`      | multilingual   | ~627 MB | Library's recommended default for max multilingual accuracy across iOS/macOS (README-recommended). |
| `large-v3-v20240930_547MB`      | multilingual   | ~547 MB | Smaller-quantized v20240930 variant. |
| `large-v3-v20240930`            | multilingual   | full    | Uncompressed v20240930 (large file). |
| `large-v3-v20240930_turbo`      | multilingual   | full    | Turbo variant — favors speed on macOS. |
| `large-v3-v20240930_turbo_632MB`| multilingual   | ~632 MB | Compressed turbo variant. |
| `large-v3`                      | multilingual   | full    | Full large-v3 (original 2023 weights). Compressed variant: `large-v3_947MB`. Turbo: `large-v3_turbo`, `large-v3_turbo_954MB`. |
| `large-v2` (+ `_949MB`, `_turbo`, `_turbo_955MB`) | multilingual | varies | Older large-v2 line. |
| `medium`, `medium.en`           | multi / en-only| —       | Larger mid-tier; multilingual `medium` for non-EN. |
| `small`, `small.en` (+ `_216MB`, `.en_217MB`) | multi / en-only | ~216 MB | Mid accuracy/size. |
| `base`, `base.en`               | multi / en-only| —       | Lower accuracy, small. |
| `tiny`, `tiny.en`               | multi / en-only| —       | Smallest, lowest accuracy — dev/debug only. |

> The `..._NNNMB` suffix in a model name is its compressed on-disk size. Models
> without a size suffix are the full (uncompressed) CoreML packages and are
> substantially larger. The full model directory list above is verified against
> the live HF repo; `recommendedModels()` picks a device-appropriate `default`
> at runtime, so the exact default can vary by device.

## Real-time / streaming

Slovo uses WhisperKit's real-time transcriber actor:

```swift
public actor AudioStreamTranscriber { /* ... */ }
```

It is constructed from the lower-level components (audioEncoder,
featureExtractor, segmentSeeker, textDecoder, tokenizer, audioProcessor) plus
`decodingOptions`, with knobs like `requiredSegmentsForConfirmation`,
`silenceThreshold`, `useVAD`, and a `stateChangeCallback`. Slovo supplies a
lock-protected `AudioProcessing` bridge so its hardened `AVAudioEngineRecorder`
remains the only microphone owner. The callback tracks confirmed segments and
the changeable tail. At key-up, Slovo stops the native loop and decodes only
audio after the last confirmed segment. A sub-second dictation, which the native
loop has not processed yet, is finalized from the beginning.

For a short final pass with a non-empty live result and no confirmed prefix
(`confirmedEndSeconds == 0`), Slovo enables word timestamps and applies the
anomaly score from OpenAI Whisper's
[silence-around-hallucinations change](https://github.com/openai/whisper/pull/1838).
The guard is deliberately stricter than the upstream heuristic: it reuses the
live text only when the final text is the same normalized prefix plus an
anomalous terminal suffix, and every suffix word starts strictly beyond the
actual recorded duration. Missing or inconsistent timestamps, a credible word,
a word that touches recorded audio, or any transcript disagreement keeps the
final decode. Long recordings do not run word alignment for this guard.

WhisperKit v1.0.0 does not yet populate `noSpeechProb`; upstream tracks that
work in [issue #27](https://github.com/argmaxinc/argmax-oss-swift/issues/27).
Its `noSpeechThreshold` therefore cannot yet reject silence inside the decoder.
Slovo does not fork or replace that mechanism: the final decode still runs, and
Slovo only validates an impossible terminal suffix afterward. When upstream
no-speech detection is implemented, it remains enabled and can prevent the
suffix before Slovo's guard is needed.

## slovo gotchas

- **Audio format:** Whisper expects **16 kHz mono Float** PCM normalized to
  roughly [-1, 1]. Resample/downmix each captured chunk before feeding the live
  input, or the output degrades. WhisperKit's
  `AudioProcessor` helpers can load/convert files, but for the in-memory buffer
  you own the resampling.
- **Resampler delay-line residue (accepted):** slovo's streaming
  `WhisperSampleConverter` reuses one `AVAudioConverter`, so its final
  ~235-frame (~15 ms) delay-line residue is never flushed at `finish()`, and that
  ~15 ms of the previous session's tail carries into the next session's first
  chunk. Same-user, in-memory, sub-phoneme trailing silence — acoustically
  immaterial for push-to-talk; documented, not fixed.
- **First-run latency:** the default flow downloads the model (hundreds of MB)
  and ANE-compiles it. Construct `WhisperKit` once at app start (with `prewarm`)
  and reuse it; never per-dictation. For a hard-offline build, bundle the
  `.mlmodelc` and pass `modelFolder` + `download: false`.
- **Compute units:** ANE (`.cpuAndNeuralEngine`) gives the best perf/Watt on
  Apple Silicon; default text-decoder compute is already
  `.cpuAndNeuralEngine`, mel default is `.cpuAndGPU`. Pin via
  `ModelComputeOptions` if you need determinism across machines.
- **Multilingual required for Russian:** pick a `large-v3*` (multilingual)
  model; `*.en` variants cannot do `language: "ru"`.
- **Result is `[TranscriptionResult]`, text is mutable+locked:** join over the
  array and read `.text`; don't assume a single element.
- **Swift 6 strict concurrency:** `v1.0.0` adopts Swift 6 concurrency and
  vendors swift-transformers internally (no transitive HF Hub dependency).
  Expect `Sendable`/actor-isolation requirements when calling from slovo's
  concurrency context.
- **Repo/URL drift:** depend on the **`argmax-oss-swift`** package and the
  **`WhisperKit`** product name. The old `WhisperKit` repo URL works via
  redirect but new docs/issues live under `argmax-oss-swift`.

## Full sources

- Repo (current/canonical): https://github.com/argmaxinc/argmax-oss-swift
- Repo (legacy URL, redirects to current): https://github.com/argmaxinc/WhisperKit
- README: https://github.com/argmaxinc/argmax-oss-swift/blob/main/README.md
- Releases (version/tag history): https://github.com/argmaxinc/argmax-oss-swift/releases
- `WhisperKit.swift` (transcribe signatures, class):
  https://github.com/argmaxinc/argmax-oss-swift/blob/main/Sources/WhisperKit/Core/WhisperKit.swift
- `Configurations.swift` (WhisperKitConfig, DecodingOptions):
  https://github.com/argmaxinc/argmax-oss-swift/blob/main/Sources/WhisperKit/Core/Configurations.swift
- `Models.swift` (TranscriptionResult, TranscriptionSegment, DecodingTask, ModelComputeOptions):
  https://github.com/argmaxinc/argmax-oss-swift/blob/main/Sources/WhisperKit/Core/Models.swift
- `AudioStreamTranscriber.swift` (streaming actor):
  https://github.com/argmaxinc/argmax-oss-swift/blob/main/Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift
- Model weights (Hugging Face): https://huggingface.co/argmaxinc/whisperkit-coreml
- Argmax product page: https://www.argmaxinc.com/blog/whisperkit
- Argmax docs: https://app.argmaxinc.com/docs

## Verification

**Date:** 2026-06-27
**Verdict:** PASS (corrections applied; no false claims remained)

**Checked (all confirmed against live canonical sources):**
- Version/status: `v1.0.0` released 2026-05-01; release history v0.16.0 (Mar 3) →
  v0.17.0 (Mar 13) → v0.18.0 (Apr 1) → v1.0.0 (May 1). v1.0.0 graduates WhisperKit
  into the multi-kit Argmax Open-Source SDK; adds Swift 6 concurrency support;
  vendors swift-transformers Hub/Tokenizers into `Sources/ArgmaxCore/External/`.
- Package/products: repo `argmaxinc/argmax-oss-swift`; products `WhisperKit`,
  `SpeakerKit`, `TTSKit`, umbrella `ArgmaxOSS`; import product `WhisperKit`;
  `.product(name: "WhisperKit", package: "argmax-oss-swift")`. License MIT.
- Platforms: WhisperKit macOS 14.0+, Xcode 16.0+ (SpeakerKit macOS 14.0+/iOS 16.0+,
  TTSKit macOS 15.0+/iOS 18.0+).
- API (verbatim, current source): `open class WhisperKit`;
  `public init(_ config: WhisperKitConfig = WhisperKitConfig()) async throws`;
  `WhisperKitConfig.init(...)` parameter list; `transcribe(audioArray:[Float],
  decodeOptions:DecodingOptions?, callback:, segmentCallback:) async throws ->
  [TranscriptionResult]`; `transcribe(audioPath:...) -> [TranscriptionResult]`;
  `DecodingOptions(task: DecodingTask = .transcribe, language: String? = nil,
  detectLanguage: Bool? = nil, wordTimestamps: Bool = false, ...)`;
  `DecodingTask` cases `transcribe`/`translate`; `ModelComputeOptions(melCompute:
  .cpuAndGPU, audioEncoderCompute: MLComputeUnits? = nil, textDecoderCompute:
  .cpuAndNeuralEngine)` — no `prefillCompute`; `open class TranscriptionResult`
  with `@TranscriptionPropertyLock` props `text/segments/language/timings/seekTime`;
  `TranscriptionSegment` props `start/end/text/tokens/avgLogprob/noSpeechProb/words?`;
  `public actor AudioStreamTranscriber`.
- Models: full `openai_whisper-*` directory list and the `large-v3-v20240930_626MB`
  contents (~627 MB; AudioEncoder/MelSpectrogram/TextDecoder `.mlmodelc`) confirmed
  on HF. README recommends `large-v3-v20240930_626MB`; `recommendedModels()` selects
  a per-device default at runtime.
- Russian/multilingual: `large-v3*` are multilingual; Russian (`language: "ru"`)
  supported by the base multilingual large-v3 weights. `*.en` variants are EN-only.

**Corrections (before → after):**
- Model table: resolved the two flagged-UNVERIFIED items. Added the full published
  variant list from the live HF repo (`large-v3`, `large-v3_947MB`,
  `large-v3_turbo`, `large-v3_turbo_954MB`, `large-v3-v20240930`,
  `large-v3-v20240930_547MB`, `large-v3-v20240930_turbo`,
  `large-v3-v20240930_turbo_632MB`, plus `large-v2*`, `medium`/`.en`,
  `small*`/`.en*`, `base`/`.en`, `tiny`/`.en`) with on-disk sizes; removed the
  `[UNVERIFIED]` flags. Added the `openai_whisper-<name>` naming note (HF folder vs
  `config.model` string) — the old doc implied a `Models/` subdir, which does not
  exist (model dirs sit at the HF repo root).
- `modelRepo` doc: clarified the init default is `nil` (effective fallback
  `argmaxinc/whisperkit-coreml`), instead of stating the default is that string.
- Install snippet: noted the README pins `from: "0.9.0"` (doc keeps `1.0.0` for the
  Swift 6 / SDK-graduated line).
- "Full sources": repointed source-file + releases links from the legacy
  `argmaxinc/WhisperKit` paths to the canonical `argmaxinc/argmax-oss-swift` paths.

**URLs validated:**
- https://github.com/argmaxinc/argmax-oss-swift (and /releases)
- https://raw.githubusercontent.com/argmaxinc/argmax-oss-swift/main/README.md
- https://raw.githubusercontent.com/argmaxinc/argmax-oss-swift/main/Sources/WhisperKit/Core/WhisperKit.swift
- .../Sources/WhisperKit/Core/Configurations.swift
- .../Sources/WhisperKit/Core/Models.swift
- https://github.com/argmaxinc/argmax-oss-swift/blob/main/Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift (exists; `Core/AudioStreamTranscriber.swift` without `Audio/` is 404)
- https://huggingface.co/argmaxinc/whisperkit-coreml (model dir listing)
- https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930_626MB

**Still-unverifiable / caveats:**
- Exact byte sizes of the no-suffix full models (`large-v3`, `large-v3-v20240930`,
  `*_turbo`) not individually opened — listed as "full"; only the `_NNNMB`-named
  variants carry a pinned size, and `_626MB` was directory-confirmed at ~627 MB.
- The legacy `argmaxinc/WhisperKit` URL serving content for source-file fetches is
  consistent with a redirect to `argmax-oss-swift`, but WebFetch does not expose
  HTTP redirect status, so "redirect vs. mirror" is inferred, not proven. Either
  way the canonical `argmax-oss-swift` URLs are correct and used in the doc.
