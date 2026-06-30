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
LOQUI_GATE_SELFTEST=red swift test --disable-automatic-resolution
```

This command is expected to fail. It proves the gate can go red when armed.

## Packaging

Package with a stable signing identity:

```sh
SIGNING_IDENTITY="Loqui Local Development" Scripts/sign-and-notarize.sh
```

The script refuses ad-hoc signing unless `ALLOW_AD_HOC_SIGNING=1` is set.

## Repository Hygiene

- Keep repository artifacts in English.
- Do not commit local databases, seed files, dotenv files, signing keys, tokens,
  or credential bundles.
- Keep workflow scratch notes outside Git.
- Update public docs when setup, privacy, packaging, or provider behavior changes.
