# slovo — Development Reference Library

Curated, source-verified API/documentation references gathered up front so v0
development doesn't stall on searching later. Each doc:

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
| [macos-fn-hotkey.md](macos-fn-hotkey.md) | `fn`/Globe as a global hotkey via an active `CGEventTap`; suppressing the OS default; Accessibility vs Input Monitoring | Apple CoreGraphics (`CGEvent.tapCreate`, `CGEventFlags`, `maskSecondaryFn`) | D1 trigger (§8) |
| [audio-capture.md](audio-capture.md) | Mic capture via `AVAudioEngine.installTap` → 16 kHz mono `Float` via `AVAudioConverter`; mic permission | Apple AVFAudio + TN3136 | `AudioRecorder` (§4/§5) |
| [asr-apple-speech.md](asr-apple-speech.md) | `SpeechAnalyzer` / `SpeechTranscriber` / `AssetInventory` on-device STT (macOS 26+); `ru_RU` | Apple Speech framework + WWDC25 277 | ASR — provisional default (§18.1); I3 gate |
| [asr-whisperkit.md](asr-whisperkit.md) | WhisperKit (`argmax-oss-swift`, product `WhisperKit`) on-device Whisper CoreML/ANE | github.com/argmaxinc/argmax-oss-swift + HF whisperkit-coreml | ASR backend (bake-off) |
| [asr-fluidaudio-parakeet.md](asr-fluidaudio-parakeet.md) | FluidAudio + Parakeet TDT v3 CoreML on the ANE; multilingual | github.com/FluidInference/FluidAudio + HF model card | ASR candidate (I3 code-switching favorite) |
| [cleanup-anthropic.md](cleanup-anthropic.md) | Anthropic Messages API, Claude Haiku 4.5, prompt caching, refusal handling (URLSession) | platform.claude.com (messages, prompt-caching, errors) | Default cleanup provider |
| [cleanup-openai.md](cleanup-openai.md) | OpenAI Responses API, `gpt-5.4-mini`, text output/refusal handling (URLSession) | platform.openai.com + developers.openai.com | Optional cleanup provider |
| [cleanup-benchmark.md](cleanup-benchmark.md) | Cleanup latency/quality benchmark, sample format, Wispr Flow reference bar, local-provider candidates | Wispr Flow pages + MLX/Qwen/Ollama official sources | Provider comparison harness |
| [cleanup-ollama.md](cleanup-ollama.md) | Ollama local HTTP API (`/api/chat`, `keep_alive`); not-running detection | github.com/ollama/ollama docs + docs.ollama.com | Local cleanup fallback (deferred past v1) |
| [storage-grdb.md](storage-grdb.md) | GRDB.swift over SQLite; `DatabaseMigrator` (create-or-get); records; `INSERT OR IGNORE` | github.com/groue/GRDB.swift (DocC) | Personalization store (§8.6) |
| [text-injection.md](text-injection.md) | Clipboard + synthetic ⌘V; secure-input gate; clipboard-manager hygiene | Apple AppKit/CoreGraphics + TN2150 + nspasteboard.org | `Injector` (§3/§11) |
| [menubar-packaging.md](menubar-packaging.md) | `NSStatusItem`, `LSUIElement`/`.accessory`, codesign/notarization, sandbox↔Accessibility conflict | Apple AppKit + Developer ID / App Sandbox docs | App shell + packaging (§9) |
| [menubar-status-ui.md](menubar-status-ui.md) | Glagolitic status icon (bundled Noto Sans Glagolitic vs LastResort tofu), `NSPopover`/`MenuBarExtra` history popover, history privacy invariant | Apple AppKit (`NSPopover`) + SwiftUI (`MenuBarExtra`) + Apple Support bundled-font lists | Status-icon + history popover (Epic 09 / §9) |

## Pending / candidate references (not yet gathered)

- CoreAudio output mute/restore for F1 — the recommendation is captured in spec
  §17 (agent `feat1-mute`); a standalone `coreaudio-mute.md` can be added if needed.
- Apple Foundation Models `LanguageModel` protocol — only when the cleanup seam
  targets it (spec §18.6 marks the protocol shape TO-VERIFY).
- GigaAM (Russian-specific ASR) — only if added as a power-mode backend.

## Verification status

All 12 docs independently verified against live canonical sources (author ≠
verifier). **9 PASS, 3 PARTIAL, 0 FAIL** — every PARTIAL was *corrected in-file*,
so all docs are now source-accurate. Each doc's full verdict (corrections
before→after, validated URLs, residual SDK/device-only gaps) is in its own
`## Verification` section.

| Doc | Verdict | Notable correction by the verifier |
|---|---|---|
| cleanup-anthropic.md | PASS | Confirmed Haiku cache minimum = exactly 4096 tokens; refusal → branch on `stop_reason` |
| cleanup-openai.md | PASS | Confirmed Responses endpoint, text input/output shape, `store`, and `gpt-5.4-mini` availability |
| cleanup-benchmark.md | PASS | Confirmed Wispr reference features; MLX/Ollama are viable benchmark candidates, with embedded MLX still requiring a product spike |
| asr-whisperkit.md | PASS | Package is `argmax-oss-swift` (product `WhisperKit`) v1.0.0; model names/sizes resolved from HF |
| asr-apple-speech.md | PASS | **`supportedLocales` is `async` (needs `await`)** — real bug; code-switching unproven (single `Locale`/session) |
| menubar-packaging.md | PASS | Confirmed sandbox⊥Accessibility; TCC grant pinned to Team ID; entitlement split |
| storage-grdb.md | PASS | `DatabaseQueue` default = DELETE/rollback (WAL only via `Configuration.journalMode=.wal`) |
| cleanup-ollama.md | PASS | API shapes / `keep_alive` semantics confirmed |
| text-injection.md | PASS | Signatures (`CGEvent` keyboard init, `IsSecureEventInputEnabled`, nspasteboard markers) confirmed |
| audio-capture.md | PARTIAL→fixed | **`audio-input` entitlement required under Hardened Runtime**; `installTap` deprecated (macOS 27) → `installAudioTap` |
| macos-fn-hotkey.md | PARTIAL→fixed | enum/flag integers all correct; "active⇒Accessibility" is practitioner-observed, not Apple doctrine → preflight both |
| asr-fluidaudio-parakeet.md | PARTIAL→fixed | transcribe API corrected (no `source:`; `loadModels`/`ASRResult`); **`TokenLanguageFilter` suppresses mixed scripts** — code-switching undocumented |

**Cross-cutting finding folded into the spec (§9, §18.8):** the permission/packaging
story (non-sandboxed + Hardened Runtime + `audio-input` entitlement + stable Team
ID + preflight Accessibility & Input Monitoring), and — load-bearing — **no ASR
candidate documents intra-utterance RU+EN code-switching**, making it the #1 v1
risk and the bake-off's primary acceptance test.
