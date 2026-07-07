# Development

## Requirements

- Apple Silicon Mac.
- macOS 26 or newer.
- Xcode with Swift 6.3 toolchain.
- Swift Package Manager.

## Build

```sh
swift build --disable-automatic-resolution
```

## Run

```sh
Scripts/build_and_run.sh --verify
```

The development run script rebuilds the `slovo` product, stages
`.build/dev-run/Slovo.app`, signs it with a stable local code-signing identity
and the app entitlements, opens the menu-bar app, and verifies that the `slovo`
process is running. Stable signing is required for macOS TCC permission
persistence; set `ALLOW_AD_HOC_SIGNING=1` only for non-persistent permission
tests.

## Test

```sh
swift test --disable-automatic-resolution
```

Use focused tests while iterating:

```sh
swift test --filter AppShellPackagingTests --disable-automatic-resolution
```

## Full Gate

Run the full local gate before committing or tagging:

```sh
Scripts/diagnose.sh
```

The gate runs build, tests, and strict lint as separate stages. This keeps one
failure from hiding another.

## Lint And Static Checks

```sh
Scripts/lint.sh
```

The lint script runs:

- explicit target dependency import checks
- shell syntax checks
- plist and entitlements linting
- strict SwiftLint
- SwiftLint analyzer checks backed by a compiler log

## Gate Self-Test

The gate has an intentional red-path check:

```sh
SLOVO_GATE_SELFTEST=red swift test --disable-automatic-resolution
```

This command is expected to fail. It proves the gate can go red when armed.

## Cleanup Benchmark

Compare cleanup candidates with the non-product benchmark executable:

```sh
swift run --disable-automatic-resolution slovo-cleanup-benchmark \
  --env-file .env \
  --providers openrouter:openai/gpt-5.4-nano,openrouter:anthropic/claude-haiku-4.5,openrouter:google/gemini-2.5-flash-lite,passthrough \
  --repetitions 10 \
  --failure-breakdown \
  --category-breakdown
```

The benchmark reads API keys from environment variables or the optional env file,
not from Keychain. It prints aggregate latency, quality counts, and optional
failure-code counts only; transcripts and cleaned output stay out of the report.
OpenRouter candidates require `OPENROUTER_API_KEY`; `passthrough` is the local
baseline and does not read network credentials.

See [cleanup-benchmark.md](references/cleanup-benchmark.md) for sample-file
format and benchmark reporting notes.

## Packaging

Packaging runs in two phases (`app`, then `dmg`); use a stable signing identity:

```sh
SIGNING_IDENTITY="Slovo Local Development" Scripts/sign-and-notarize.sh app
```

The script refuses ad-hoc signing unless `ALLOW_AD_HOC_SIGNING=1` is set. See
[release-checklist.md](release-checklist.md) for the full flow; stapling the
notarization ticket is the only manual step.

## Repository Hygiene

- Keep repository artifacts in English.
- Do not commit local databases, seed files, dotenv files, signing keys, tokens,
  or credential bundles.
- Keep workflow scratch notes outside Git.
- Update public docs when setup, privacy, packaging, or cleanup behavior changes.
