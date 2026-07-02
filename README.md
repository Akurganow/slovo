# Slovo

Slovo is an experimental macOS menu-bar dictation app for Apple Silicon. Hold the
`fn` / Globe key, speak, release, and Slovo inserts the dictated text into the
focused field.

The privacy boundary is deliberately narrow: raw audio stays on the Mac. Cleanup
is always attempted through OpenRouter; only the already-transcribed text is sent
for model-routed text cleanup.

## Status

Current release: `v0.2.0`

This is an early developer release. The app is usable, but performance tuning,
Developer ID signing, notarization, and broader installer packaging are still in
progress.

## Features

- Push-to-talk dictation from the global `fn` / Globe key.
- Local speech capture and on-device transcription through WhisperKit
  (Whisper large-v3 turbo), including mixed Russian + English in one utterance.
- Text cleanup through OpenRouter, with curated routed models and custom
  OpenRouter model ids.
- OpenRouter API key stored in macOS Keychain and read only when cleanup runs.
- Clipboard-based text insertion with secure-input checks and clipboard restore.
- Local SQLite personalization store for vocabulary hints.
- Menu-bar status glyphs for idle, recording, and processing states.
- Strict Swift build, test, concurrency, lint, and static guard checks.

## Privacy Model

Slovo has two different data paths:

- Audio path: microphone audio is captured and transcribed locally through
  WhisperKit. Raw audio never leaves the machine. The Whisper model itself is a
  third-party asset: WhisperKit downloads it once (from Hugging Face) on first
  use and caches it under Application Support; transcription then runs fully
  on-device with no per-dictation network calls.
- Cleanup path: transcript text is sent to OpenRouter when cleanup is available.
  OpenRouter routes the request to the selected model id.

Secrets are not stored in the repository. The OpenRouter API key is stored as a
macOS Keychain item. Local personalization databases, seed files, dotenv files,
signing keys, and credential bundles are ignored by Git.

## Requirements

- Apple Silicon Mac.
- macOS 26 or newer.
- Xcode with Swift 6.3 toolchain.
- A stable code-signing identity for local app packaging.
- Microphone and Accessibility permissions. Input Monitoring may be requested
  only as a targeted hotkey recovery step if the event tap cannot start.
- On first use, WhisperKit downloads the Whisper model over the network; after
  that, transcription is fully on-device.
- First-run setup tracks only the proven blockers: Microphone and Accessibility.
- OpenRouter API key for cleanup.

## Build And Test

Install dependencies through Swift Package Manager using the checked-in
`Package.resolved` file:

```sh
swift build --disable-automatic-resolution
swift test --disable-automatic-resolution
```

Run the full local gate before shipping changes:

```sh
Scripts/diagnose.sh
```

`Scripts/diagnose.sh` runs build, tests, and strict lint as independent stages so
one failure does not hide another.

Compare cleanup latency and quality with the non-product benchmark:

```sh
swift run --disable-automatic-resolution slovo-cleanup-benchmark \
  --env-file .env \
  --providers openrouter:openai/gpt-5.4-nano,openrouter:anthropic/claude-haiku-4.5,openrouter:google/gemini-3.1-flash-lite,openrouter:qwen/qwen3.6-flash,openrouter:mistralai/mistral-small-2603,passthrough \
  --repetitions 10 \
  --failure-breakdown \
  --category-breakdown
```

Latest live OpenRouter benchmark snapshot, measured on 2026-07-02 with 10
repetitions over the 30-sample `slovo-cleanup-v1` suite, using the exact
request the app sends (reasoning disabled via `reasoning: {effort: "none"}`).

| Candidate | Runs | Passed | Errors | p50 | p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `openrouter:anthropic/claude-haiku-4.5` | 300 | 230 | 0 | 1270.8 ms | 3408.4 ms |
| `openrouter:deepseek/deepseek-v4-flash` | 300 | 217 | 1 | 1617.0 ms | 5302.0 ms |
| `openrouter:qwen/qwen3.6-flash` | 300 | 216 | 1 | 797.3 ms | 2859.7 ms |
| `openrouter:mistralai/mistral-small-2603` | 300 | 214 | 0 | 524.8 ms | 3556.3 ms |
| `openrouter:openai/gpt-5.4-nano` | 300 | 209 | 0 | 824.0 ms | 2550.8 ms |
| `openrouter:google/gemini-3.1-flash-lite` | 300 | 207 | 0 | 786.3 ms | 3132.0 ms |
| `passthrough:none` | 300 | 0 | 0 | 0.0 ms | 0.0 ms |

### Cleanup model reference numbers

Public reference numbers for the curated catalog models. Retrieved 2026-07-02.
Sources: OpenRouter catalog API (pricing), Artificial Analysis Intelligence
Index v4.1 leaderboard (intelligence, output speed, first-answer-token
latency), AA-Omniscience hallucination rates via the BenchLM aggregator
(medium extraction confidence). Cleanup does not use reasoning mode, so the
table shows non-reasoning figures; `n/a` marks values published only for
reasoning mode or models absent from the leaderboard.

| Model | Price in/out, $/1M | Intelligence Index | Hallucination rate | Output speed | First-token latency |
| --- | ---: | ---: | ---: | ---: | ---: |
| `openai/gpt-5.4-nano` (default) | 0.20 / 1.25 | 24 | 73.6% | 140.6 t/s | n/a |
| `anthropic/claude-haiku-4.5` | 1.00 / 5.00 | 24 | n/a | 92.4 t/s | 0.93 s |
| `google/gemini-3.1-flash-lite` | 0.25 / 1.50 | 25 | 81.6% | 294 t/s | 5.2 s |
| `qwen/qwen3.6-flash` | 0.19 / 1.13 | n/a | n/a | n/a | n/a |
| `deepseek/deepseek-v4-flash` | 0.09 / 0.18 | n/a | 89.7% | 105 t/s | n/a |
| `mistralai/mistral-small-2603` | 0.15 / 0.60 | 20 | 66.8% | 173 t/s | 0.81 s |

`n/a` means the model is absent from that public leaderboard as of the
retrieval date. Public multilingual leaderboards (Global-MMLU-Lite, MMMLU)
do not cover Russian, so Russian-specific quality is not represented by any
number above; the `slovo-cleanup-v1` suite is the project's own measurement
on dictation-style samples.

## Run Locally

For a fast signed development launch, build and open a staged menu-bar bundle:

```sh
script/build_and_run.sh --verify
```

The script rebuilds the `slovo` product, stages `.build/dev-run/Slovo.app`, signs
it with a stable local code-signing identity and the app entitlements, opens it,
and verifies that the `slovo` process is running. Stable signing is required for
macOS TCC permission persistence.

Package and sign the app with a stable identity:

```sh
SIGNING_IDENTITY="Slovo Local Development" Scripts/sign-and-notarize.sh
open .build/dist/Slovo.app
```

The signing script intentionally rejects ad-hoc signing by default because macOS
privacy grants and Keychain trust are tied to a stable app identity. For local
experiments only, ad-hoc signing can be forced:

```sh
ALLOW_AD_HOC_SIGNING=1 SIGNING_IDENTITY=- Scripts/sign-and-notarize.sh
```

After first launch, grant the requested setup permissions in System Settings,
then use the Slovo menu to retry setup and enter the OpenRouter key.

## Configuration

Runtime settings are stored in `UserDefaults`. The OpenRouter API key is stored
in Keychain:

- OpenRouter service/account: `slovo` / `openrouter-api-key`
- ASR backend/model: `whisperkit` / `large-v3-v20240930_turbo_632MB`

The app also accepts an environment variable as a development-only override:

- `OPENROUTER_API_KEY`

If cleanup is unavailable, misconfigured, or refused, Slovo inserts the direct
transcript instead of dropping the dictation. The menu-bar glyph briefly switches
to the Glagolitic letter `Ⱁ` in the error tint, then returns to idle.

## Documentation

- [Architecture](docs/architecture.md)
- [Privacy and security](docs/privacy.md)
- [Development](docs/development.md)
- [Development reference library](docs/references/README.md)
- [Release checklist](docs/release-checklist.md)
- [Cleanup benchmark reference](docs/references/cleanup-benchmark.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The short version: keep changes small,
run `Scripts/diagnose.sh`, do not commit secrets or local personalization data,
and document behavior changes in English.

## Security

See [SECURITY.md](SECURITY.md). Please do not include API keys, transcripts,
personal vocabulary, local databases, or private work terminology in public
issues.

## License

GNU General Public License v3.0. See [LICENSE](LICENSE).

Slovo is copyleft: any distributed work based on this source must itself be
released under the GPLv3. The bundled dependencies (GRDB.swift, argmax-oss-swift
/ WhisperKit) are MIT-licensed and compatible with this license.
