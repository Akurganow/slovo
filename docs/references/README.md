# slovo — Development Reference Library

Curated, source-verified API/documentation references for the platform APIs
Slovo depends on, kept as maintenance material. Each doc:

- cites the **canonical full source(s)** (Apple Developer docs, official repos,
  model cards) — links are mandatory;
- was written by a gatherer agent, then **independently verified** by a separate
  agent (author ≠ verifier) against the live sources;
- carries a `## Verification` section at its end with the verdict
  (PASS / PARTIAL / FAIL), corrections applied (before→after), the source URLs
  validated, and any items only confirmable on a real macOS SDK / Xcode.

This is the public reference layer for the APIs and platform behavior Slovo
depends on. The personalization seed data lives under `../../data/` and is
**gitignored** — it is not part of this library.

## Catalog

| Doc | Covers | Primary canonical source(s) | slovo role |
|---|---|---|---|
| [macos-fn-hotkey.md](macos-fn-hotkey.md) | `fn`/Globe as a global hotkey via an active `CGEventTap`; suppressing the OS default; Accessibility vs Input Monitoring | Apple CoreGraphics (`CGEvent.tapCreate`, `CGEventFlags`, `maskSecondaryFn`) | Push-to-talk trigger (`CGEventTapHotkeyMonitor`) |
| [audio-capture.md](audio-capture.md) | Mic capture via `AVAudioEngine.installTap` → 16 kHz mono `Float` via `AVAudioConverter`; mic permission | Apple AVFAudio + TN3136 | `AudioRecorder` / `AVAudioEngineRecorder` |
| [asr-apple-speech.md](asr-apple-speech.md) | `DictationTranscriber` / `SpeechAnalyzer` / `AssetInventory` on-device STT (macOS 26+); `ru_RU` | Apple Speech framework + WWDC25 277 | Superseded ASR research; the Apple Speech transcriber was deleted from the codebase (see asr-engine-selection.md) |
| [asr-whisperkit.md](asr-whisperkit.md) | WhisperKit (`argmax-oss-swift`, product `WhisperKit`) on-device Whisper CoreML/ANE | github.com/argmaxinc/argmax-oss-swift + HF whisperkit-coreml | Runtime ASR engine (Whisper large-v3 turbo) |
| [asr-fluidaudio-parakeet.md](asr-fluidaudio-parakeet.md) | FluidAudio + Parakeet TDT v3 CoreML on the ANE; multilingual | github.com/FluidInference/FluidAudio + HF model card | Archived historical ASR comparison; not linked by runtime |
| [asr-engine-selection.md](asr-engine-selection.md) | 42-engine ASR survey gated on RU+EN intra-utterance code-switching; why WhisperKit large-v3 stays the runtime path over Apple Speech; the on-device acceptance-test protocol | Multi-agent adversarial survey of HF model cards, arXiv/Interspeech papers, Apple/WWDC | ASR engine decision record — the "why" behind asr-whisperkit.md (the Apple-Speech and Parakeet notes point here) |
| [cleanup-benchmark.md](cleanup-benchmark.md) | Cleanup latency/quality benchmark, sample format, OpenRouter-routed candidates | OpenRouter sources | Cleanup comparison harness |
| [storage-grdb.md](storage-grdb.md) | GRDB.swift over SQLite; `DatabaseMigrator` (create-or-get); records; `INSERT OR IGNORE` | github.com/groue/GRDB.swift (DocC) | Personalization store (`GRDBPersonalizationSource`) |
| [text-injection.md](text-injection.md) | Clipboard + synthetic ⌘V; secure-input gate; clipboard-manager hygiene | Apple AppKit/CoreGraphics + TN2150 + nspasteboard.org | `ClipboardPasteInjector` |
| [menubar-packaging.md](menubar-packaging.md) | `NSStatusItem`, `LSUIElement`/`.accessory`, codesign/notarization, sandbox↔Accessibility conflict | Apple AppKit + Developer ID / App Sandbox docs | App shell + packaging |
| [menubar-status-ui.md](menubar-status-ui.md) | Glagolitic status icon (bundled Noto Sans Glagolitic vs LastResort tofu) | Apple AppKit + Apple Support bundled-font lists | Status-icon glyphs (shipped) |

## Pending references (not yet gathered)

- Apple Foundation Models `LanguageModel` protocol — only if the cleanup seam
  ever targets it (the cleanup path is OpenRouter-only today).
- GigaAM (Russian-specific ASR) — historical note only; alternative ASR backends
  are not product candidates while the runtime ASR engine is WhisperKit
  (Whisper large-v3 turbo).
- CoreAudio output mute/restore — no standalone reference needed: the feature
  shipped small (`Sources/SlovoCore/Audio/CoreAudioOutputMute.swift`,
  `SystemAudioController.swift`).

## Verification status

All current docs were independently verified against live canonical sources
(author ≠ verifier). **7 PASS, 3 PARTIAL, 0 FAIL** — every PARTIAL was *corrected in-file*,
so all docs are now source-accurate. Each doc's full verdict (corrections
before→after, validated URLs, residual SDK/device-only gaps) is in its own
`## Verification` section.

| Doc | Verdict | Notable correction by the verifier |
|---|---|---|
| cleanup-benchmark.md | PASS | OpenRouter-only benchmark path updated; `passthrough` kept as local baseline |
| asr-whisperkit.md | PASS | Archived historical reference; package is `argmax-oss-swift` (product `WhisperKit`) v1.0.0; model names/sizes resolved from HF |
| asr-apple-speech.md | PASS | **`supportedLocales` is `async` (needs `await`)** — real bug; code-switching unproven (single `Locale`/session) |
| menubar-packaging.md | PASS | Confirmed sandbox⊥Accessibility; TCC grant pinned to Team ID; entitlement split |
| menubar-status-ui.md | PASS | Glagolitic status glyphs render through bundled Noto Sans Glagolitic when pinned explicitly |
| storage-grdb.md | PASS | `DatabaseQueue` default = DELETE/rollback (WAL only via `Configuration.journalMode=.wal`) |
| text-injection.md | PASS | Signatures (`CGEvent` keyboard init, `IsSecureEventInputEnabled`, nspasteboard markers) confirmed |
| audio-capture.md | PARTIAL→fixed | **`audio-input` entitlement required under Hardened Runtime**; `installTap` deprecated (macOS 27) → `installAudioTap` |
| macos-fn-hotkey.md | PARTIAL→fixed | enum/flag integers all correct; "active⇒Accessibility" is practitioner-observed, not Apple doctrine → preflight both |
| asr-fluidaudio-parakeet.md | PARTIAL→fixed | transcribe API corrected (no `source:`; `loadModels`/`ASRResult`); **`TokenLanguageFilter` suppresses mixed scripts** — code-switching undocumented |

**Cross-cutting finding:** the permission/packaging
story (non-sandboxed + Hardened Runtime + `audio-input` entitlement + stable Team
ID + preflight Accessibility & Input Monitoring). The runtime ASR engine is
WhisperKit (Whisper large-v3 turbo); the Apple Speech notes are superseded
research (see asr-engine-selection.md), not the active path.
