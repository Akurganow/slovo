# Release Checklist

Use this checklist before publishing a Slovo build or tag.

## Automated Gate

Run the full local gate:

```sh
Scripts/diagnose.sh
```

The gate must pass build, tests, strict lint, and analyzer checks. Also verify the
gate can fail intentionally:

```sh
SLOVO_GATE_SELFTEST=red swift test --disable-automatic-resolution
```

The self-test command is expected to exit non-zero.

## App Packaging

Package with a stable development signing identity or a Developer ID identity:

```sh
SIGNING_IDENTITY="Slovo Local Development" Scripts/sign-and-notarize.sh
```

The app bundle must use `LSUIElement=true` and a stable bundle identifier. Avoid
ad-hoc signing for release validation because it cannot prove that TCC grants
survive rebuild.

Verify the signed bundle:

```sh
codesign --verify --deep --strict --verbose=2 .build/dist/Slovo.app
spctl --assess --type execute --verbose .build/dist/Slovo.app
```

When a notarization profile is available, set `NOTARY_PROFILE` and confirm the
script runs `notarytool` and `stapler`.

## Manual L4 Checks

- first launch shows setup only when required permissions are missing.
- Microphone, Accessibility, and Input Monitoring prompts or deep links lead to
  the correct System Settings panes.
- TCC grants survive rebuild when the signing identity is stable.
- The menu-bar icon renders through `NotoSansGlagolitic-Regular`; recording,
  processing, and idle states are visually distinct.
- Holding `fn` starts capture, releasing `fn` stops capture, restores audio, and
  inserts text into a normal text field.
- Secure-input fields fail closed without writing transcript text to the
  clipboard.
- Offline or refused cleanup falls back to `PassThrough` and preserves the user's
  words.
- The OpenRouter key is read from Keychain once at startup and cached in memory
  for normal cleanup calls.
- `biasTerms` reach the transcriber path on a real on-device run.
- privacy holds: raw audio stays local, secrets are never logged, and transcript
  text leaves the machine only through OpenRouter when cleanup is enabled.
