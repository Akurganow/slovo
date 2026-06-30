# Contributing

Thanks for taking the time to improve Slovo.

## Development Setup

Requirements:

- Apple Silicon Mac.
- macOS 26 or newer.
- Xcode with Swift 6.3 toolchain.
- A stable code-signing identity for packaged app testing.

Install Swift package dependencies from the checked-in lockfile:

```sh
swift build --disable-automatic-resolution
```

Run the full local gate before opening a pull request:

```sh
Scripts/diagnose.sh
```

## Project Rules

- Keep raw audio local. Only transcript text may leave the machine for cleanup.
- Store API keys only in Keychain or development-only environment variables.
- Never commit `.env`, signing keys, credential files, local databases, or seed
  files.
- Keep comments short and focused on intent or invariants.
- Prefer small, behavior-focused pull requests.
- Update documentation when user-visible behavior, setup, privacy, or release
  workflow changes.

## Tests

Slovo uses Swift Testing and source-tree gate checks. New behavior should have a
test that can fail on a concrete broken implementation, not just pass on the
current code.

Useful commands:

```sh
swift test --disable-automatic-resolution
Scripts/lint.sh
Scripts/diagnose.sh
```

## Packaging

Local packaging requires a stable signing identity:

```sh
SIGNING_IDENTITY="Slovo Local Development" Scripts/sign-and-notarize.sh
```

The script refuses ad-hoc signing unless `ALLOW_AD_HOC_SIGNING=1` is set, because
ad-hoc builds cannot prove stable macOS privacy or Keychain trust behavior.

## Pull Request Checklist

- [ ] The change is scoped to one behavior or documentation goal.
- [ ] `Scripts/diagnose.sh` passes locally.
- [ ] No secrets, local databases, seeds, or signing material are staged.
- [ ] User-facing behavior changes are documented.
- [ ] Security or privacy boundary changes are called out explicitly.
