# Apple Speech (SpeechAnalyzer / SpeechTranscriber)

## Purpose

`SpeechAnalyzer` + `SpeechTranscriber` are the new on-device speech-to-text APIs Apple
introduced at WWDC25 (macOS 26 "Tahoe" generation, all platforms are `26.0+`). This is
slovo's **only runtime ASR backend**: a native Swift, fully on-device transcription
engine for Apple Silicon, the same technology that powers system Notes / Voice Memos /
Journal / Call Summarization.

The design splits three responsibilities:

- **`SpeechAnalyzer`** — an `actor` that owns an analysis *session*. You give it audio
  (an async input sequence) and one or more *modules*; it drives the analysis.
- **`SpeechTranscriber`** — a *module* you add to the analyzer that performs the actual
  speech-to-text. Reading its `results` async sequence gives you transcripts.
- **`AssetInventory`** — manages the per-locale ML model assets (download / install /
  reserve). Transcription is on-device, but the language models must be fetched first.

> [!IMPORTANT]
> For slovo's **short push-to-talk dictation**, evaluate **`DictationTranscriber`** instead
> of `SpeechTranscriber`. Apple's own abstracts: `SpeechTranscriber` is "appropriate for
> normal conversation and general purposes" (WWDC25 framing: long-form audio, "optimized
> for lectures, meetings, and conversations"), while `DictationTranscriber` is "similar to
> system dictation features and compatible with older devices" — it "uses the same
> speech-to-text machine learning models as system dictation features do, or as
> `SFSpeechRecognizer` does when it is configured for on-device operation." Both are modules
> that plug into the same `SpeechAnalyzer`. See [slovo gotchas](#slovo-gotchas). The task
> framed `SpeechTranscriber` as the default; this distinction is a decision point, not a
> contradiction.

## Key types / APIs

All declarations below are taken verbatim from Apple's documentation. Availability for
every type listed: **iOS / iPadOS / Mac Catalyst / macOS / tvOS / visionOS 26.0+**
(`DictationTranscriber` omits tvOS).

### `SpeechAnalyzer`

```swift
final actor SpeechAnalyzer
```

```swift
// Create an analyzer with a set of modules.
convenience init(modules: [any SpeechModule], options: SpeechAnalyzer.Options?)

// Create an analyzer AND begin analysis on a live input sequence.
convenience init<InputSequence>(
    inputSequence: InputSequence,
    modules: [any SpeechModule],
    options: SpeechAnalyzer.Options?,
    analysisContext: AnalysisContext,
    volatileRangeChangedHandler: sending ((CMTimeRange, Bool, Bool) -> Void)?
) async

// Streaming: start analysis of an async input sequence and return immediately.
func start<InputSequence>(inputSequence: InputSequence) async throws

// Batch: analyze a full file, returning when the file has been read.
func analyzeSequence(from: AVAudioFile) async throws -> CMTime?

// Finish once the terminated input is fully consumed and results are finalized.
func finalizeAndFinishThroughEndOfInput() async throws
func finalizeAndFinish(through: CMTime) async throws
func cancelAndFinishNow() async

// Static: best on-device audio format the given modules can consume.
static func bestAvailableAudioFormat(compatibleWith: [any SpeechModule]) async -> AVAudioFormat?
```

`InputSequence` is any `AsyncSequence` whose element is `AnalyzerInput`. The usual pattern
is `AsyncStream<AnalyzerInput>.makeStream()`, passing the stream to `start(inputSequence:)`
and yielding buffers through the continuation. Other relevant members verified in the docs:
`prepareToAnalyze(in:)` (warm up with minimal startup delay), `setModules(_:)`,
`setContext(_:)` / `context`, `volatileRange`. There is also a file-based pair —
`init(inputAudioFile:modules:options:analysisContext:finishAfterFile:volatileRangeChangedHandler:)`
and `start(inputAudioFile:finishAfterFile:)` — if you already have an `AVAudioFile`.

`SpeechAnalyzer.Options` (verified fields on developer.apple.com): `ignoresResourceLimits:
Bool` [beta] (ignore predefined system resource limits), `priority` (priority of analysis
work), and the nested `ModelRetention` enum — a model-caching strategy that delays or
prevents unloading of analyzer resources across sessions. The `init(modules:options:)`
signature is `convenience init(modules: [any SpeechModule], options: SpeechAnalyzer.Options?
= nil)`, so `SpeechAnalyzer(modules: [transcriber])` (as used below) is valid — `options`
defaults to `nil`.

### `AnalyzerInput`

```swift
struct AnalyzerInput

init(buffer: AVAudioPCMBuffer)
init(buffer: AVAudioPCMBuffer, bufferStartTime: CMTime?)  // for discontiguous audio

let bufferStartTime: CMTime?
let bufferFormat: AVAudioFormat   // [beta] the audio format of this input
```

A time-coded chunk of audio. You wrap each captured `AVAudioPCMBuffer` (after converting
it to the analyzer's preferred format) in an `AnalyzerInput` and yield it into the input
sequence.

### `SpeechTranscriber`

```swift
final class SpeechTranscriber
// Abstract (verbatim): "A speech-to-text transcription module that's appropriate for
// normal conversation and general purposes."

// Full configuration init.
convenience init(
    locale: Locale,
    transcriptionOptions: Set<SpeechTranscriber.TranscriptionOption>,
    reportingOptions: Set<SpeechTranscriber.ReportingOption>,
    attributeOptions: Set<SpeechTranscriber.ResultAttributeOption>
)
convenience init(locale: Locale, preset: SpeechTranscriber.Preset)

// Locales that CAN be transcribed (including not-yet-downloaded, downloadable ones).
// NOTE: this is an ASYNC getter — you must `await` it.
static var supportedLocales: [Locale] { get async }
// Locales whose models are actually installed on this device right now. Also ASYNC.
static var installedLocales: [Locale] { get async }
static func supportedLocale(equivalentTo: Locale) async -> Locale?

// Whether this module can run given the device's hardware/capabilities.
static var isAvailable: Bool

// The async sequence of transcription results.
var results: some Sendable & AsyncSequence<SpeechTranscriber.Result, any Error>
```

> [!WARNING]
> `supportedLocales` and `installedLocales` are **async** properties
> (`{ get async }` per developer.apple.com) — they must be `await`ed, not read
> synchronously. The `static var isAvailable: Bool` is the canonical runtime check for
> "can this device run the transcriber at all".

`ReportingOption` (verified cases): `.volatileResults` ("Provides tentative results for an
audio range in addition to the finalized result"), `.alternativeTranscriptions`,
`.fastResults` ("Biases the transcriber towards responsiveness, yielding faster but also
less accurate results").
`ResultAttributeOption` (verified cases): `.audioTimeRange`, `.transcriptionConfidence`.

### `SpeechTranscriber.Result`

```swift
struct Result

var text: AttributedString          // most likely interpretation for this range
let alternatives: [AttributedString] // descending likelihood (needs .alternativeTranscriptions)
var range: CMTimeRange              // audio range this result covers
var isFinal: Bool                   // true once finalized; false while volatile
var resultsFinalizationTime: CMTime // results final up to (not including) this time
```

The same phrase may be emitted multiple times: first as **volatile** (`isFinal == false`)
tentative guesses that improve, then once as a **finalized** result (`isFinal == true`).
Display volatile text live for responsiveness; commit the finalized text.

### `AssetInventory`

```swift
final class AssetInventory

// Build a request that downloads the models the given modules need.
static func assetInstallationRequest(supporting: [any SpeechModule]) async throws
    -> AssetInstallationRequest?

// Reservations: keep a locale's model resident (apps have a small limit).
static func reserve(locale: Locale) async throws -> Bool
static func release(reservedLocale: Locale) async -> Bool
static var reservedLocales: [Locale]
static var maximumReservedLocales: Int

static func status(forModules: [any SpeechModule]) async -> AssetInventory.Status
```

```swift
// On the returned request object (AssetInstallationRequest):
@objc final class AssetInstallationRequest   // conforms to NSProgressReporting
func downloadAndInstall() async throws
var progress: Progress   // from NSProgressReporting — observe for download UI
```

`AssetInstallationRequest` conforms to `NSProgressReporting`
([developer.apple.com](https://developer.apple.com/documentation/speech/assetinstallationrequest)),
so the `progress: Progress` property is real (the protocol mandates it). WWDC25 session 277
demonstrates exactly this: `self.downloadProgress = downloader.progress`.

## Minimal Swift example (analyze a buffer, get final transcript, ru_RU)

```swift
import Speech
import AVFoundation

@available(macOS 26.0, *)
func transcribeRussian() async throws -> String {
    let locale = Locale(identifier: "ru_RU")   // Russian — confirmed supported (see below)

    // 1. Ensure the ru_RU model is available, downloading it if needed.
    //    supportedLocales / installedLocales are ASYNC — note the `await`.
    guard await SpeechTranscriber.supportedLocales.contains(where: {
        $0.identifier(.bcp47) == locale.identifier(.bcp47)
    }) else { throw NSError(domain: "slovo", code: 1) }   // locale not supported

    let transcriber = SpeechTranscriber(
        locale: locale,
        transcriptionOptions: [],
        reportingOptions: [.volatileResults],     // live partials
        attributeOptions: [.audioTimeRange]       // time-coded output
    )

    if await !SpeechTranscriber.installedLocales.contains(where: {
        $0.identifier(.bcp47) == locale.identifier(.bcp47)
    }) {
        if let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            try await request.downloadAndInstall()   // on-device fetch, observe .progress for UI
        }
    }

    // 2. Build the analyzer and a live input stream.
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
    try await analyzer.start(inputSequence: inputSequence)

    // 3. Consume results concurrently.
    let collected = Task { () -> String in
        var finalText = AttributedString()
        for try await result in transcriber.results where result.isFinal {
            finalText += result.text
        }
        return String(finalText.characters)
    }

    // 4. Feed audio. Convert your capture buffers to the analyzer's preferred format first.
    let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
        compatibleWith: [transcriber]
    )
    // ... for each captured AVAudioPCMBuffer `buf` (converted to analyzerFormat via
    //     AVAudioConverter):
    //     inputBuilder.yield(AnalyzerInput(buffer: convertedBuffer))

    // 5. End of push-to-talk: terminate input, flush, await final transcript.
    inputBuilder.finish()
    try await analyzer.finalizeAndFinishThroughEndOfInput()
    return try await collected.value
}
```

> [!NOTE]
> The microphone-capture + `AVAudioConverter` plumbing (steps 4) is elided. Capture with
> `AVAudioEngine.inputNode`, convert each tap buffer to `analyzerFormat`, then
> `yield(AnalyzerInput(buffer:))`. `bestAvailableAudioFormat` returns the format the
> installed model prefers — convert to it rather than assuming a fixed sample rate.

## slovo gotchas

- **Russian and English are confirmed supported.** `SpeechTranscriber.supportedLocales`
  includes `ru_RU` and the full English family (`en_US`, `en_GB`, `en_AU`, `en_CA`,
  `en_IN`, `en_IE`, `en_NZ`, `en_SG`, `en_ZA`) — confirmed by two independent published
  enumerations of the macOS 26 list (see sources). Always check at runtime against
  `supportedLocales`; do not hard-code the list. Remember `supportedLocales` /
  `installedLocales` are **async** (`await` them).
- **One locale per transcriber — no documented intra-utterance RU+EN code-switching.**
  This is project-defining for slovo, so be precise: a `SpeechTranscriber` /
  `DictationTranscriber` is constructed with a **single** `locale: Locale`, and **no Apple
  documentation, WWDC25 session 277 material, or the sample article states that one session
  transcribes mixed Cyrillic+Latin (RU+EN) within a single utterance.** The supported-/
  installed-locale docs are silent on multi-language sessions; the API shape (one locale per
  module) implies one language per session. Do **not** assume code-switching works. If slovo
  needs mixed RU+EN in one breath, this must be **empirically tested** on-device (and may
  require running two transcribers, language pre-detection, or an alternate backend). Treat
  "handles code-switching" as **unproven** until measured, not as a feature Apple promises.
- **`supportedLocales` ≠ `installedLocales`.** A supported locale's model may not be on the
  device. Gate transcription on `installedLocales`; if missing, trigger
  `AssetInventory.assetInstallationRequest(supporting:)` → `downloadAndInstall()` and show
  the request's `progress` to the user. First run for a new language downloads hundreds of
  MB; budget for it.
- **Use Apple-managed retention.** `SpeechAnalyzer.Options.ModelRetention` controls
  whether analyzer resources linger across sessions. Slovo maps positive
  `keepWarmSeconds` values to `.lingering` and zero to `.whileInUse`; it does not
  own a manual ASR model lifecycle or unload timer. `AssetInventory.reserve(locale:)`
  remains available for locale reservation when the runtime needs the OS to keep a
  language model resident, subject to `maximumReservedLocales`.
- **OS version gate.** Every type here is `macOS 26.0+` (confirmed on each type's
  developer.apple.com page; `DictationTranscriber` omits tvOS, all others list iOS / iPadOS
  / Mac Catalyst / macOS / tvOS / visionOS 26.0+). Guard all usage with
  `if #available(macOS 26.0, *)` / `@available(macOS 26.0, *)` and keep a fallback path
  (older `SFSpeechRecognizer`, or an alternate backend) for pre-Tahoe Macs — slovo targets
  Apple Silicon but not necessarily only macOS 26.
- **Hardware gate is runtime, not just OS.** Apple does not publish a minimum-chip
  requirement; instead `SpeechTranscriber.isAvailable` (`static var isAvailable: Bool`) is
  the canonical runtime check for whether the device's hardware/capabilities can run the
  transcriber, and `supportedLocales` returns empty when unsupported. Gate on `isAvailable`
  and fall back to `DictationTranscriber` ("compatible with older devices") or
  `SFSpeechRecognizer` rather than assuming a specific Mac will work.
- **Push-to-talk fit: prefer `DictationTranscriber` for short clips.** `SpeechTranscriber`
  is tuned for long sustained audio; `DictationTranscriber` matches short dictation
  utterances (the `SFSpeechRecognizer` replacement) and is the better match for slovo's
  hold-to-talk model. It uses the same on-device dictation models and the *same* analyzer /
  asset / results machinery (same `supportedLocales` / `installedLocales`, same `results`
  stream). The init shape is *similar but not identical*: `DictationTranscriber`'s full init
  adds a `contentHints: Set<DictationTranscriber.ContentHint>` parameter (e.g. `.farField`,
  `customizedLanguage(modelConfiguration:)`) absent from `SpeechTranscriber`, so a swap is
  cheap but not a literal drop-in.
  **Decide which to ship per measured latency/accuracy on real ru/en push-to-talk clips.**
- **Streaming vs batch.** Both work. For live PTT use `start(inputSequence:)` + an
  `AsyncStream` and read partials via `.volatileResults`. If you instead record the whole
  clip first, `analyzeSequence(from: AVAudioFile)` is the one-shot batch path. End a PTT
  session with `inputBuilder.finish()` then `finalizeAndFinishThroughEndOfInput()` to flush
  the last finalized result.
- **Convert audio to the model's format.** Use
  `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` and an `AVAudioConverter`;
  don't assume 16 kHz or the mic's native format.
- **Authorization (partly verified — see caveat).** `NSMicrophoneUsageDescription` +
  record-permission for `AVAudioEngine` capture is independently certain. For *speech*
  authorization: the canonical Apple page for
  `SFSpeechRecognizer.requestAuthorization(_:)` states verbatim — "Your app's `Info.plist`
  file must contain the `NSSpeechRecognitionUsageDescription` key with a valid usage
  description. If this key is not present, your app will crash when you call this method."
  However, **no canonical Apple page located in this pass states that the *new*
  `SpeechAnalyzer`/`SpeechTranscriber` path requires `SFSpeechRecognizer.requestAuthorization`
  or `NSSpeechRecognitionUsageDescription`** — the new Speech framework pages (SpeechAnalyzer,
  SpeechTranscriber, AssetInventory) say nothing about authorization. The reuse-the-same-key
  claim comes from secondary write-ups, not one Apple sentence. **Safe assumption:** add
  `NSSpeechRecognitionUsageDescription` (harmless if unneeded) and request Speech
  authorization, but confirm the actual requirement against the Xcode SDK / sample project
  on a real machine — it may be unnecessary for the fully-on-device new API.

## Open items (still need an SDK / on-device check)

Most of the originally-flagged items were resolved against developer.apple.com during
verification (see the `## Verification` section). What genuinely remains open — because it
needs the Xcode SDK headers or a real device, not a doc page:

- **Whether the *new* API requires `NSSpeechRecognitionUsageDescription` / Speech
  authorization at all.** The new Speech framework pages (`SpeechAnalyzer`,
  `SpeechTranscriber`, `AssetInventory`) say nothing about authorization; only the legacy
  `SFSpeechRecognizer.requestAuthorization(_:)` page mandates the key (and crashes without
  it). It is plausible the fully-on-device new path needs *only* microphone permission.
  Confirm against the SDK / sample project. (Microphone permission for `AVAudioEngine` is
  certain regardless.)
- **`DictationTranscriber` vs `SpeechTranscriber` latency/accuracy for short PTT** — Apple's
  abstracts establish the positioning (conversation/general-purpose vs dictation-like /
  older-device-compatible) but give no benchmark. Must be measured on real slovo ru/en clips.
- **Intra-utterance RU+EN code-switching** — *not* documented anywhere (see the gotcha
  above). The single-`locale` API shape implies one language per session. Must be empirically
  tested on-device; do not assume it works.
- **Exact minimum hardware.** No published minimum chip. The runtime gate is
  `SpeechTranscriber.isAvailable` (and empty `supportedLocales` when unsupported); test on
  the target Mac rather than promising support from a spec sheet.

## Full sources

Canonical (developer.apple.com):

- SpeechAnalyzer — https://developer.apple.com/documentation/speech/speechanalyzer
- SpeechTranscriber — https://developer.apple.com/documentation/speech/speechtranscriber
- SpeechTranscriber.Result — https://developer.apple.com/documentation/speech/speechtranscriber/result
- SpeechTranscriber.ReportingOption — https://developer.apple.com/documentation/speech/speechtranscriber/reportingoption
- SpeechTranscriber.ResultAttributeOption — https://developer.apple.com/documentation/speech/speechtranscriber/resultattributeoption
- DictationTranscriber — https://developer.apple.com/documentation/speech/dictationtranscriber
- AnalyzerInput — https://developer.apple.com/documentation/speech/analyzerinput
- AssetInventory — https://developer.apple.com/documentation/speech/assetinventory
- AssetInstallationRequest (NSProgressReporting → `progress`) — https://developer.apple.com/documentation/speech/assetinstallationrequest
- SpeechTranscriber.supportedLocales (async getter) — https://developer.apple.com/documentation/speech/speechtranscriber/supportedlocales
- SpeechTranscriber.installedLocales (async getter) — https://developer.apple.com/documentation/speech/speechtranscriber/installedlocales
- Speech framework (overview) — https://developer.apple.com/documentation/speech/
- Bringing advanced speech-to-text capabilities to your app (article + sample code) —
  https://developer.apple.com/documentation/Speech/bringing-advanced-speech-to-text-capabilities-to-your-app
- Recognizing speech in live audio — https://developer.apple.com/documentation/Speech/recognizing-speech-in-live-audio
- SFSpeechRecognizer.requestAuthorization(_:) (authorization + Info.plist key) —
  https://developer.apple.com/documentation/speech/sfspeechrecognizer/requestauthorization(_:)
- WWDC25 Session 277 "Bring advanced speech-to-text to your app with SpeechAnalyzer" —
  https://developer.apple.com/videos/play/wwdc2025/277/

Secondary (cross-checked, not authoritative — used only for usage patterns / the
authorization claim):

- Crosley, "Apple's New Speech Framework: SpeechAnalyzer vs SFSpeechRecognizer" —
  https://blakecrosley.com/blog/speech-framework-vs-sfspeechrecognizer
- WWDC25 session transcripts (gist) —
  https://gist.github.com/auramagi/9c040c2233dfe71c24c76942e186f788
- Gubarenko, "iOS 26: SpeechAnalyzer Guide" (full supportedLocales enumeration) —
  https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide
- arshtechpro, "WWDC 2025 — The Next Evolution of Speech-to-Text using SpeechAnalyzer"
  (long-form positioning; `downloader.progress`) —
  https://dev.to/arshtechpro/wwdc-2025-the-next-evolution-of-speech-to-text-using-speechanalyzer-6lo

## Verification

- **Date:** 2026-06-27
- **Verdict:** PASS (with one real correction applied; remaining gaps are SDK/device-only,
  not doc errors)
- **Method:** Independent verification by a non-author agent. Fetched the underlying
  documentation JSON for each type (e.g.
  `…/tutorials/data/documentation/speech/speechtranscriber.json`) to read real Swift
  declarations rather than the JS-rendered HTML, plus the WWDC25-session write-up and two
  independent locale enumerations.

**What was checked and confirmed against developer.apple.com:**
- Type declarations: `final actor SpeechAnalyzer`; `final class SpeechTranscriber`;
  `final class DictationTranscriber`; `@objc final class AssetInstallationRequest`;
  `final class AssetInventory` — all match.
- All `SpeechAnalyzer` methods/inits used in the doc verified, incl.
  `init(modules:options:)` with `options: SpeechAnalyzer.Options? = nil` (so the one-arg
  call in the example is valid), `start(inputSequence:)`, `analyzeSequence(from:)`,
  `finalizeAndFinishThroughEndOfInput()`, `finalizeAndFinish(through:)`,
  `cancelAndFinishNow()`, `bestAvailableAudioFormat(compatibleWith:)`, `prepareToAnalyze`,
  `setModules`, `setContext`/`context`, `volatileRange`.
- `SpeechAnalyzer.Options` fields confirmed: `ignoresResourceLimits: Bool` [beta],
  `priority`, nested `ModelRetention` enum (model-caching strategy). (Was flagged
  unverified; now confirmed.)
- `SpeechTranscriber.ReportingOption` cases `.volatileResults`, `.alternativeTranscriptions`,
  `.fastResults` and their quoted abstracts — verbatim-correct.
  `SpeechTranscriber.Result` fields (`text: AttributedString`, `alternatives`,
  `range: CMTimeRange`, `isFinal: Bool`, `resultsFinalizationTime: CMTime`) — correct.
- `AssetInventory` API (`assetInstallationRequest(supporting:)`, `reserve(locale:)`,
  `release(reservedLocale:)`, `reservedLocales`, `maximumReservedLocales`,
  `status(forModules:)`) — all match.
- **`AssetInstallationRequest.progress`** (was flagged unverified) — now **confirmed**:
  the class conforms to `NSProgressReporting`, which mandates `var progress: Progress`, and
  WWDC25 session 277 shows `self.downloadProgress = downloader.progress`.
- **`supportedLocales` includes `ru_RU` and the full English family** — confirmed by two
  independent published enumerations of the macOS 26 list (Gubarenko guide + a second
  enumeration), both listing `ru_RU`, `en_US`, `en_GB`, `en_AU`, `en_CA`, `en_IN`, `en_IE`,
  `en_NZ`, `en_SG`, `en_ZA` (among ~42 locales).
- Availability `macOS 26.0+` (and the iOS/iPadOS/Catalyst/tvOS/visionOS 26.0+ set) confirmed
  on each type's page; `DictationTranscriber` correctly omits tvOS.
- `DictationTranscriber` abstract ("similar to system dictation features and compatible with
  older devices"; same models as `SFSpeechRecognizer` on-device) confirmed.

**Corrections made (before → after):**
1. **`supportedLocales` / `installedLocales` are async (real bug).**
   Before: `static var supportedLocales: [Locale]` and example used
   `SpeechTranscriber.supportedLocales.contains(...)` / `!SpeechTranscriber.installedLocales…`
   synchronously.
   After: declared `{ get async }`, added an explicit warning, and added `await` to both
   uses in the example (`await SpeechTranscriber.supportedLocales…`,
   `await !SpeechTranscriber.installedLocales…`). Source: the canonical supportedlocales /
   installedlocales pages both show `{ get async }`.
2. **`SpeechTranscriber` positioning quote.** Before: "tuned for *sustained* transcription
   'over minutes or hours'" (no canonical source for that quote).
   After: Apple's real abstract, "appropriate for normal conversation and general purposes"
   (+ WWDC25 long-form framing). The decision-point with `DictationTranscriber` is kept.
3. **`AssetInstallationRequest.progress`** upgraded from `[UNVERIFIED]` to confirmed (with
   the `NSProgressReporting` + WWDC-code evidence) and shown in the API block.
4. **`SpeechAnalyzer.Options` fields** upgraded from `[UNVERIFIED]` to confirmed declarations.
5. **`isAvailable`** added (canonical hardware-capability runtime gate) and woven into the
   hardware gotcha, replacing the speculative "Apple Silicon / Neural Engine requirement".
6. **`DictationTranscriber` init shape** corrected: not an "identical init shape" — its full
   init adds a `contentHints` parameter `SpeechTranscriber` lacks; "similar, not a literal
   drop-in".
7. **Authorization** reworded to reflect ground truth: the canonical crash-without-the-key
   sentence is documented only for *legacy* `SFSpeechRecognizer.requestAuthorization(_:)`;
   **no** Apple page ties the *new* `SpeechAnalyzer`/`SpeechTranscriber` path to
   `NSSpeechRecognitionUsageDescription`. Kept as a safe-default-but-verify item.
8. Added a **code-switching gotcha** and added the async-locale pages +
   `AssetInstallationRequest` page to canonical sources.

**Code-switching finding (project-defining):** No Apple documentation, WWDC25 session 277
material, or the official sample article states that `SpeechTranscriber` (or
`DictationTranscriber`) handles **intra-utterance RU+EN code-switching** (mixed
Cyrillic+Latin in one utterance). The `supportedLocales` / `installedLocales` docs are
explicitly silent on multi-language sessions, and the API constructs a transcriber from a
**single** `locale: Locale`, which implies one language per session. The doc must **not**
claim code-switching works; it now flags this as unproven and requiring on-device testing
(possibly two transcribers / language pre-detection / an alternate backend).

**Still unverifiable from public sources (needs Xcode SDK or a real device):**
- Whether the *new* API actually requires Speech authorization / the Info.plist key at all
  (only legacy `SFSpeechRecognizer` is documented to). Needs SDK / sample project.
- `DictationTranscriber` vs `SpeechTranscriber` measured latency/accuracy for short PTT.
- Whether RU+EN code-switching works in practice (see above).
- Exact minimum hardware (no published minimum; gate at runtime on `isAvailable`).
