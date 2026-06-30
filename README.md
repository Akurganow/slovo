# Loqui

Loqui is an experimental macOS menu-bar dictation app for Apple Silicon. Hold the
`fn` / Globe key, speak, release, and Loqui inserts the dictated text into the
focused field.

The privacy boundary is deliberately narrow: raw audio stays on the Mac. If cloud
cleanup is enabled, only the already-transcribed text is sent to the selected text
cleanup provider.

## Status

Current release: `v0.0.1`

This is an early developer release. The app is usable, but performance tuning,
Developer ID signing, notarization, and broader installer packaging are still in
progress.

## Features

- Push-to-talk dictation from the global `fn` / Globe key.
- Local speech capture and on-device transcription through the configured ASR
  backend.
- Optional cleanup through Anthropic or OpenAI, with provider-specific model
  selection.
- Provider API keys stored in macOS Keychain and cached in memory after startup.
- Clipboard-based text insertion with secure-input checks and clipboard restore.
- Local SQLite personalization store for vocabulary hints.
- Menu-bar status glyphs for idle, recording, and processing states.
- Strict Swift build, test, concurrency, lint, and static guard checks.

## Privacy Model

Loqui has two different data paths:

- Audio path: microphone audio is captured and transcribed locally.
- Cleanup path: transcript text may be sent to the selected cleanup provider when
  cleanup is enabled.

Secrets are not stored in the repository. Anthropic and OpenAI API keys are
stored as separate macOS Keychain items. Local personalization databases, seed
files, dotenv files, signing keys, and credential bundles are ignored by Git.

## Requirements

- Apple Silicon Mac.
- macOS 26 or newer.
- Xcode with Swift 6.3 toolchain.
- A stable code-signing identity for local app packaging.
- Microphone, Accessibility, and Input Monitoring permissions.
- Anthropic or OpenAI API key if cloud cleanup is enabled.

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

## Run Locally

Package and sign the app with a stable identity:

```sh
SIGNING_IDENTITY="Loqui Local Development" Scripts/sign-and-notarize.sh
open .build/dist/Loqui.app
```

The signing script intentionally rejects ad-hoc signing by default because macOS
privacy grants and Keychain trust are tied to a stable app identity. For local
experiments only, ad-hoc signing can be forced:

```sh
ALLOW_AD_HOC_SIGNING=1 SIGNING_IDENTITY=- Scripts/sign-and-notarize.sh
```

After first launch, grant the requested permissions in System Settings, then use
the Loqui menu to retry setup and enter provider keys.

## Configuration

Runtime settings are stored in `UserDefaults`. Provider API keys are stored in
Keychain:

- Anthropic service/account: `loqui` / `anthropic-api-key`
- OpenAI service/account: `loqui` / `openai-api-key`

The app also accepts environment variables as development-only overrides:

- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`

## Documentation

- [Architecture](docs/architecture.md)
- [Privacy and security](docs/privacy.md)
- [Development](docs/development.md)
- [Development reference library](docs/references/README.md)
- [Release checklist](docs/release-checklist.md)
- [OpenAI cleanup reference](docs/references/cleanup-openai.md)
- [Anthropic cleanup reference](docs/references/cleanup-anthropic.md)

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
