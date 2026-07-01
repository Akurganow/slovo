# Slovo

Slovo is an experimental macOS menu-bar dictation app for Apple Silicon. Hold the
`fn` / Globe key, speak, release, and Slovo inserts the dictated text into the
focused field.

The privacy boundary is deliberately narrow: raw audio stays on the Mac. If
cleanup is enabled, only the already-transcribed text is sent to OpenRouter for
model-routed text cleanup.

## Status

Current release: `v0.0.1`

This is an early developer release. The app is usable, but performance tuning,
Developer ID signing, notarization, and broader installer packaging are still in
progress.

## Features

- Push-to-talk dictation from the global `fn` / Globe key.
- Local speech capture and on-device transcription through the configured ASR
  backend.
- Optional text cleanup through OpenRouter, with curated routed models and custom
  OpenRouter model ids.
- OpenRouter API key stored in macOS Keychain and cached in memory after startup.
- Clipboard-based text insertion with secure-input checks and clipboard restore.
- Local SQLite personalization store for vocabulary hints.
- Menu-bar status glyphs for idle, recording, and processing states.
- Strict Swift build, test, concurrency, lint, and static guard checks.

## Privacy Model

Slovo has two different data paths:

- Audio path: microphone audio is captured and transcribed locally.
- Cleanup path: transcript text may be sent to OpenRouter when cleanup is
  enabled. OpenRouter routes the request to the selected model id.

Secrets are not stored in the repository. The OpenRouter API key is stored as a
macOS Keychain item. Local personalization databases, seed files, dotenv files,
signing keys, and credential bundles are ignored by Git.

## Requirements

- Apple Silicon Mac.
- macOS 26 or newer.
- Xcode with Swift 6.3 toolchain.
- A stable code-signing identity for local app packaging.
- Microphone, Accessibility, and Input Monitoring permissions.
- OpenRouter API key if cleanup is enabled.

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
  --providers openrouter:openai/gpt-5.4-nano,openrouter:anthropic/claude-haiku-4.5,openrouter:google/gemini-2.5-flash-lite,passthrough \
  --repetitions 10 \
  --failure-breakdown \
  --category-breakdown
```

Latest live OpenRouter benchmark snapshot, measured on 2026-07-01 with 10
repetitions over the 30-sample `slovo-cleanup-v1` suite. The curated shortlist
was selected from OpenRouter catalog metadata and fast-model comparisons, then
validated through this benchmark.

| Candidate | Runs | Passed | Errors | p50 | p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `openrouter:anthropic/claude-haiku-4.5` | 300 | 230 | 0 | 1198.1 ms | 2659.0 ms |
| `openrouter:openai/gpt-5.4-nano` | 300 | 211 | 0 | 787.5 ms | 3054.2 ms |
| `openrouter:google/gemini-2.5-flash-lite` | 300 | 184 | 1 | 524.5 ms | 1893.6 ms |
| `passthrough:none` | 300 | 0 | 0 | 0.0 ms | 0.0 ms |

## Run Locally

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

After first launch, grant the requested permissions in System Settings, then use
the Slovo menu to retry setup and enter the OpenRouter key.

## Configuration

Runtime settings are stored in `UserDefaults`. The OpenRouter API key is stored
in Keychain:

- OpenRouter service/account: `slovo` / `openrouter-api-key`

The app also accepts an environment variable as a development-only override:

- `OPENROUTER_API_KEY`

If cleanup is unavailable, Slovo inserts the direct transcript instead of
dropping the dictation. The menu-bar glyph briefly switches to the Glagolitic
letter `Ⱁ` in the error tint, then returns to idle.

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

MIT. See [LICENSE](LICENSE).
