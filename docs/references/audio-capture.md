# Audio capture (mic → 16 kHz mono)

## Purpose

slovo captures microphone audio during a push-to-talk window and feeds it to an
ASR model that expects **16 kHz, mono, 32-bit float, non-interleaved** PCM. The
microphone hardware almost never delivers that format natively (Apple Silicon
built-in mics and most USB/Bluetooth devices run at 44.1 kHz or 48 kHz, often
mono but sometimes stereo). This document is the authoritative reference for the
two things slovo must do:

1. Capture raw microphone buffers with `AVAudioEngine` + an input tap.
2. Convert each captured buffer to the ASR target format with `AVAudioConverter`
   and feed it to live recognition while the key is held.

It also covers the macOS microphone-permission flow, which is mandatory before
any capture can succeed.

All APIs below are verified against current Apple Developer documentation; see
[Full sources](#full-sources). Platform availability is given per symbol so you
can confirm the macOS deployment target slovo needs.

## Key APIs (signatures)

### Capture — `AVAudioEngine` / `AVAudioInputNode`

```swift
// AVAudioEngine — macOS 10.10+
var inputNode: AVAudioInputNode { get }   // singleton, created on demand
func start() throws                        // begins rendering; can throw
func stop()                                // stops; taps remain installed
func prepare()                             // preallocates resources (optional)

// AVAudioNode.installTap — macOS 10.10+; DEPRECATED in macOS 27.0
func installTap(onBus bus: AVAudioNodeBus,
                bufferSize: AVAudioFrameCount,
                format: AVAudioFormat?,
                block tapBlock: @escaping AVAudioNodeTapBlock)
func removeTap(onBus bus: AVAudioNodeBus)   // NOT deprecated

// AVAudioNodeTapBlock = (AVAudioPCMBuffer, AVAudioTime) -> Void

// Replacement introduced in macOS 27.0 (use when targeting 27.0+):
func installAudioTap(onBus bus: AVAudioNodeBus,
                     bufferSize: AVAudioFrameCount,
                     format: AVAudioFormat?,
                     tapProvider: @escaping @Sendable
                       (AVReadOnlyAudioPCMBuffer, AVAudioTime) -> Void) throws
```

> **Deprecation note.** `installTap(onBus:bufferSize:format:block:)` is deprecated
> as of **macOS 27.0** in favor of `installAudioTap(onBus:bufferSize:format:tapProvider:)`
> (a `throws`ing call whose tap block is `@Sendable` and delivers
> `AVReadOnlyAudioPCMBuffer`). `installTap` still functions; on any macOS
> deployment target below 27.0 it remains the only option, so the example below
> uses it. When slovo's deployment target reaches macOS 27.0, migrate to
> `installAudioTap` (note its block hands you a *read-only* buffer, so copy the
> samples you need out of it). `removeTap(onBus:)` is unchanged and not deprecated.

Notes from Apple's docs:

- The input node is a **singleton created on demand** the first time you read
  `inputNode`. To receive input, install a recording tap on it.
- Check the input node's **hardware input format** for a nonzero sample rate and
  channel count to confirm input is enabled; trying to start input when it is
  unavailable causes the engine to throw or raise an exception.
- You can install/remove taps while the engine is running, but **only one tap per
  bus**.
- The tap block **may be invoked on a thread other than the main thread** — keep
  it cheap and do not touch UI from it.

### Conversion — `AVAudioFormat`, `AVAudioPCMBuffer`, `AVAudioConverter`

```swift
// AVAudioFormat — macOS 10.10+
init?(commonFormat format: AVAudioCommonFormat,   // e.g. .pcmFormatFloat32
      sampleRate: Double,                          // 16000
      channels: AVAudioChannelCount,               // 1
      interleaved: Bool)                           // false (deinterleaved float)

// AVAudioPCMBuffer — macOS 10.10+
init?(pcmFormat format: AVAudioFormat,
      frameCapacity: AVAudioFrameCount)

// AVAudioConverter — macOS 10.11+
init?(from sourceFormat: AVAudioFormat, to destinationFormat: AVAudioFormat)

func convert(to outputBuffer: AVAudioBuffer,
             error outError: NSErrorPointer,
             withInputFrom inputBlock: AVAudioConverterInputBlock)
    -> AVAudioConverterOutputStatus

// AVAudioConverterInputBlock =
//   (AVAudioPacketCount, UnsafeMutablePointer<AVAudioConverterInputStatus>)
//     -> AVAudioBuffer?
```

Status enums:

- `AVAudioConverterInputStatus`: `.haveData`, `.noDataNow`, `.endOfStream`
- `AVAudioConverterOutputStatus`: `.haveData`, `.inputRanDry`, `.endOfStream`,
  `.error`

The simpler `convert(to:from:)` exists but **cannot do sample-rate conversion** —
slovo must use the `withInputFrom:` callback form because mic rate ≠ 16 kHz.

### Permission — `AVCaptureDevice` and `AVAudioApplication`

```swift
// AVCaptureDevice — macOS 10.14+
class func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus
class func requestAccess(for mediaType: AVMediaType) async -> Bool
class func requestAccess(for mediaType: AVMediaType,
                         completionHandler handler: @escaping @Sendable (Bool) -> Void)
// AVAuthorizationStatus: .notDetermined, .restricted, .denied, .authorized

// AVAudioApplication — macOS 14.0+ (also iOS 17 / visionOS 1)
class func requestRecordPermission() async -> Bool
class func requestRecordPermission(
    completionHandler response: @escaping @Sendable (Bool) -> Void)
var recordPermission: AVAudioApplication.recordPermission { get }
// recordPermission: .undetermined, .granted, .denied
```

**Which to use on macOS — resolved.** `AVAudioApplication.requestRecordPermission`
is verified available on **macOS 14.0+**, so it is usable on a modern macOS
target. But neither API is the *only required* gate: both consult the same
system microphone privacy (TCC) authorization, so checking either is sufficient.
The real, OS-enforced requirements are the `NSMicrophoneUsageDescription`
Info.plist key and (for Hardened Runtime apps — see below) the audio-input
entitlement; **the chosen request API is the trigger for the TCC prompt, not the
gate itself.**

Apple's canonical macOS capture guidance ("Requesting authorization to capture
and save media") is built entirely around **`AVCaptureDevice` with
`AVMediaType.audio`** — it does not mention `AVAudioApplication` or
`AVAudioSession` at all. `AVCaptureDevice` is therefore the broadly documented,
lower-deployment-target path (macOS 10.14+) for an `AVAudioEngine`-based capture
app on macOS. **Recommendation for slovo: use `AVCaptureDevice` with
`.audio`** (as the example does). It is the documented path, has a lower
deployment floor, and is exactly what the system-level TCC requirement keys off
of. Use `AVAudioApplication.requestRecordPermission` only if slovo deliberately
adopts that API; there is no documented requirement to do so for AVAudioEngine
input on macOS.

### Info.plist / entitlements (mandatory)

- `NSMicrophoneUsageDescription` (String): purpose string shown in the system
  permission prompt. Apple marks it **required** ("This key is required if your
  app uses APIs that access the device's microphone"), and the capture-authorization
  guide states that without the appropriate key/entitlement in place before
  requesting authorization, **"the system terminates your app."**
- `com.apple.security.device.audio-input` entitlement — required for **Hardened
  Runtime** apps that ship outside the Mac App Store, NOT just sandboxed apps.
  Apple's docs tie it to enabling Hardened Runtime (Xcode → Resource Access →
  Audio Input), and TCC denies the mic to a hardened-runtime binary lacking it
  ("kTCCServiceMicrophone requires entitlement com.apple.security.device.audio-input").
  **This applies to slovo even though slovo is non-sandboxed:** notarized macOS
  apps distributed outside the App Store use Hardened Runtime, so slovo must add
  this entitlement (it is the App-Sandbox status that is irrelevant here, not the
  entitlement). The earlier assumption that the entitlement is sandbox-only is
  wrong for slovo's distribution model.

## Minimal Swift example

End-to-end: request permission, install a tap, and stream each converted 16 kHz
mono Float32 chunk to recognition.

```swift
import AVFoundation

final class MicCapture {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let onSamples: @Sendable ([Float]) -> Void

    /// ASR target: 16 kHz, mono, 32-bit float, deinterleaved.
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false)!

    init(onSamples: @escaping @Sendable ([Float]) -> Void) {
        self.onSamples = onSamples
    }

    // MARK: Permission

    /// Resolves once the user has answered (or had previously answered) the prompt.
    func ensureMicPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:    return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default:             return false   // .denied / .restricted
        }
    }

    // MARK: Capture (key down)

    func start() throws {
        let input = engine.inputNode
        // Hardware-native format on bus 0 (e.g. 48 kHz, 1–2 ch). Source of truth.
        let hwFormat = input.outputFormat(forBus: 0)

        // Build the converter from the live hardware format to the ASR format.
        converter = AVAudioConverter(from: hwFormat, to: targetFormat)
        // Tap with format: nil to receive buffers in the node's own format.
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            self?.append(buffer)   // runs off the main thread
        }

        engine.prepare()
        try engine.start()
    }

    // MARK: Stop (key up)

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
    }

    // MARK: Conversion

    private func append(_ source: AVAudioPCMBuffer) {
        guard let converter else { return }

        // Output capacity scaled by the sample-rate ratio, with headroom.
        let ratio = targetFormat.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                         frameCapacity: capacity) else { return }

        // Feed `source` exactly once; report end-of-stream on the next request so
        // the converter flushes the resampler tail instead of blocking for more.
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow   // or .endOfStream to flush
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return source
        }

        guard status != .error,
              let channel = out.floatChannelData?[0] else {
            if let error { print("convert failed: \(error.localizedDescription)") }
            return
        }
        onSamples(Array(UnsafeBufferPointer(start: channel,
                                            count: Int(out.frameLength))))
    }
}
```

The conversion pattern matches Apple's TN3136 model: reuse one converter for the
session, drive it from the input callback, and read `floatChannelData[0]` for
mono output. Slovo immediately forwards each resulting chunk to live recognition.

## slovo gotchas

- **Never hardcode the source format.** Read `inputNode.outputFormat(forBus: 0)`
  at capture start and build the converter from it. The user can switch mics
  (AirPods 24 kHz vs. built-in 48 kHz) between sessions; a stale converter
  resamples from the wrong rate and produces garbage or wrong-speed audio.
- **Stereo → mono.** Some inputs report 2 channels. Letting `AVAudioConverter`
  target a 1-channel format performs the downmix for you; do not assume mono.
- **`format: nil` vs. explicit format on the tap.** Passing `nil` gives buffers
  in the node's native format (recommended — let the converter do all the work).
  If you pass an explicit format it must be compatible with the node's format or
  the tap install fails. Do not try to make the tap itself output 16 kHz; the tap
  is not a resampler.
- **Tap block runs off the main thread.** Keep `append` allocation-light and
  never touch UI or AppKit from it. Forward each converted chunk to the
  recognition stream.
- **Permission timing.** Call `ensureMicPermission()` *before* `engine.start()`.
  Starting the engine without authorization throws / raises. On first launch the
  prompt is async — the very first push-to-talk may need to await the user's
  answer before any audio is captured.
- **Buffer-size latency tradeoff.** `bufferSize: 4096` at 48 kHz ≈ 85 ms of audio
  per callback. For snappier push-to-talk feedback use a smaller size (e.g. 1024
  ≈ 21 ms); it is a hint, the system may deliver a different size. Smaller =
  lower latency, more callbacks.
- **Sample-rate-conversion tail.** Resampling has internal priming/latency, so a
  short utterance can lose a few frames at the boundary if you never flush. On
  `stop()`, optionally run one final `convert` with `inputStatus = .endOfStream`
  to drain the converter's remaining output (TN3136). For dictation the loss is
  usually inaudible, but flush if the ASR is sensitive to clipped word endings.
- **Engine restart.** Build a fresh `AVAudioEngine` per capture and observe
  `AVAudioEngineConfigurationChange`. Reusing one engine across sessions caches
  the input hardware format, so after an audio device change (e.g. unplugging
  headphones) `installTap` asserts `format.sampleRate == hwFormat.sampleRate`,
  raises an `NSException`, and the process aborts. A fresh engine re-queries the
  current device; the small startup cost is acceptable for push-to-talk.

## Full sources

Canonical Apple Developer documentation (verified):

- AVAudioEngine: https://developer.apple.com/documentation/avfaudio/avaudioengine
- AVAudioEngine.inputNode: https://developer.apple.com/documentation/avfaudio/avaudioengine/inputnode
- AVAudioEngine.start(): https://developer.apple.com/documentation/avfaudio/avaudioengine/start()
- AVAudioNode.installTap(onBus:bufferSize:format:block:) (deprecated macOS 27.0): https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:)
- AVAudioNode.installAudioTap(onBus:bufferSize:format:tapProvider:) (replacement, macOS 27.0+): https://developer.apple.com/documentation/avfaudio/avaudionode/installaudiotap(onbus:buffersize:format:tapprovider:)
- AVAudioConverter: https://developer.apple.com/documentation/avfaudio/avaudioconverter
- AVAudioConverter.convert(to:error:withInputFrom:): https://developer.apple.com/documentation/avfaudio/avaudioconverter/convert(to:error:withinputfrom:)
- AVAudioConverterInputBlock: https://developer.apple.com/documentation/avfaudio/avaudioconverterinputblock
- AVAudioConverterInputStatus: https://developer.apple.com/documentation/avfaudio/avaudioconverterinputstatus
- AVAudioConverterOutputStatus: https://developer.apple.com/documentation/avfaudio/avaudioconverteroutputstatus
- TN3136: AVAudioConverter — performing sample rate conversions: https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions
- AVAudioFormat.init(commonFormat:sampleRate:channels:interleaved:): https://developer.apple.com/documentation/avfaudio/avaudioformat/init(commonformat:samplerate:channels:interleaved:)
- AVAudioPCMBuffer.init(pcmFormat:frameCapacity:): https://developer.apple.com/documentation/avfaudio/avaudiopcmbuffer/init(pcmformat:framecapacity:)-5jhd5
- AVCaptureDevice.authorizationStatus(for:): https://developer.apple.com/documentation/avfoundation/avcapturedevice/authorizationstatus(for:)
- AVCaptureDevice.requestAccess(for:completionHandler:): https://developer.apple.com/documentation/avfoundation/avcapturedevice/requestaccess(for:completionhandler:)
- AVAudioApplication.requestRecordPermission(completionHandler:): https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission(completionhandler:)
- AVAudioApplication.recordPermission: https://developer.apple.com/documentation/avfaudio/avaudioapplication/recordpermission-swift.property
- Requesting authorization to capture and save media: https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media
- NSMicrophoneUsageDescription: https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSMicrophoneUsageDescription
- Audio Input Entitlement (com.apple.security.device.audio-input): https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.device.audio-input
- Hardened Runtime: https://developer.apple.com/documentation/security/hardened-runtime

## Verification

Date: 2026-06-27

Verdict: PARTIAL

Independent verification by a verifier who did not author this doc, against live
Apple Developer documentation (JSON doc endpoints + TN3136).

Checked:
- `AVAudioNode.installTap(onBus:bufferSize:format:block:)` — signature, macOS
  availability, `format: nil` semantics.
- `AVAudioNode.installAudioTap(onBus:bufferSize:format:tapProvider:)` — existence,
  signature, availability (newly discovered replacement API).
- `AVAudioConverter.convert(to:error:withInputFrom:)` — signature, return type,
  availability, and TN3136 sample-rate-conversion pattern.
- `AVAudioApplication.requestRecordPermission` (+ `recordPermission`) — macOS 14.0+
  availability across platforms.
- `AVCaptureDevice.authorizationStatus(for:)` and `requestAccess(for:)` (sync +
  async) — signatures and availability.
- "Requesting authorization to capture and save media" — which API it recommends
  for mic on macOS, and its termination warning.
- `NSMicrophoneUsageDescription` Info.plist key and
  `com.apple.security.device.audio-input` entitlement — requirement scope.

Corrections (before -> after):
- installTap deprecation: doc presented `installTap(...)` as the current API with
  no deprecation note -> added note that it is DEPRECATED in macOS 27.0, with the
  replacement `installAudioTap(onBus:bufferSize:format:tapProvider:)` (macOS 27.0+,
  `throws`, `@Sendable` block delivering `AVReadOnlyAudioPCMBuffer`). Example still
  uses `installTap` (valid below 27.0); migration guidance added.
- Entitlement scope: "Sandboxed macOS apps also need the
  `com.apple.security.device.audio-input` entitlement" -> corrected to: required
  for Hardened Runtime apps shipping outside the Mac App Store (which includes
  non-sandboxed-but-notarized apps like slovo), tied to Hardened Runtime, not the
  App Sandbox. Explicitly flagged that this DOES apply to slovo despite slovo being
  non-sandboxed.
- Permission-gate `[UNVERIFIED]` flag: removed and resolved (see conclusion below).
- NSMicrophoneUsageDescription wording: tightened to quote the actual Apple
  statements ("required if your app uses APIs that access the microphone";
  capture guide: "the system terminates your app" when the key/entitlement is
  missing before requesting authorization).

Confirmed correct as written (no change needed):
- `convert(to:error:withInputFrom:)` signature/return type and "the simpler
  `convert(to:from:)` cannot do sample-rate conversion" — matches Apple + TN3136.
- `AVAudioFormat.init(commonFormat:sampleRate:channels:interleaved:)`,
  `AVAudioPCMBuffer.init(pcmFormat:frameCapacity:)` shapes.
- `AVCaptureDevice` permission API signatures and macOS 10.14+ availability; async
  `requestAccess(for:) async -> Bool` exists.
- `AVAudioApplication.requestRecordPermission` macOS 14.0+ availability.
- `format: nil` on the tap yields the node's native format (verified against the
  installTap format-parameter discussion).

Permission-gate conclusion (the question the author flagged):
`AVAudioApplication.recordPermission`/`requestRecordPermission` is NOT a *required*
gate for `AVAudioEngine` input on macOS, and neither is `AVCaptureDevice` the
required gate in the API sense. Both request APIs trigger the SAME system
microphone privacy (TCC) authorization; checking/requesting via either is
sufficient. The OS-enforced requirements are the `NSMicrophoneUsageDescription`
key and the audio-input entitlement (for Hardened Runtime). Apple's canonical
macOS capture guidance is written exclusively around `AVCaptureDevice` with
`.audio` and never mentions `AVAudioApplication`/`AVAudioSession`, so
`AVCaptureDevice` is the recommended path for slovo (documented, lower deployment
floor). Recommendation: keep the `AVCaptureDevice` approach the example uses.

URLs validated (HTTP 200, content matched):
- https://developer.apple.com/documentation/avfaudio/avaudionode/installtap(onbus:buffersize:format:block:)
- https://developer.apple.com/documentation/avfaudio/avaudionode/installaudiotap(onbus:buffersize:format:tapprovider:)
- https://developer.apple.com/documentation/avfaudio/avaudioconverter/convert(to:error:withinputfrom:)
- https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions
- https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission(completionhandler:)
- https://developer.apple.com/documentation/avfoundation/avcapturedevice/authorizationstatus(for:)
- https://developer.apple.com/documentation/avfoundation/avcapturedevice/requestaccess(for:completionhandler:)
- https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media
- https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSMicrophoneUsageDescription
- https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.device.audio-input

Still unverifiable / caveats:
- TN3136's published example only demonstrates the `.haveData` (infinite-provider)
  case; it does not itself show `.endOfStream`/`.noDataNow` or an explicit tail-flush
  snippet. The doc's flush-on-stop guidance is a sound application of the documented
  status enum values (`AVAudioConverterInputStatus.endOfStream` is real and
  verified) but is NOT a verbatim TN3136 recipe. The doc's "TN3136 model" phrasing
  is reasonable for converter reuse + callback-driven conversion, which TN3136 does
  show; the specific end-of-stream flush is an extrapolation, not a direct quote.
- macOS 27.0 is the current release cycle; the `installTap` deprecation and the
  `installAudioTap` replacement are recent. The example intentionally still uses
  `installTap` for compatibility with sub-27.0 deployment targets.
