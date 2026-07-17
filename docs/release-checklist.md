# Release Checklist

Use this checklist before publishing a Slovo build or tag.

## Automated CI/CD

Pushing a `v*` tag runs the full pipeline on GitHub-hosted macOS runners — tests,
Developer ID signing, notarization, **stapling**, and a published GitHub Release
with the stapled DMG and app zip. Because CI staples on a clean network, it is the
first place the whole chain finishes end to end. See
[release-ci.md](release-ci.md) for the one-time secret setup and the trigger/verify
flow. The steps below remain the reference for local, manual packaging and for
verifying a build before tagging.

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

Packaging runs in two automated phases. The only manual step is stapling the
notarization ticket, which must run on a Mac that can reach Apple's notarization
service. Use a stable development signing identity or a Developer ID identity;
avoid ad-hoc signing for release validation because it cannot prove that TCC
grants survive rebuild. The app bundle must use `LSUIElement=true` and a stable
bundle identifier.

Set `NOTARY_PROFILE` (a `notarytool` keychain profile) to notarize locally;
without it a phase stops after signing. CI notarizes with an App Store Connect API
key instead (`NOTARY_KEY_P8` / `NOTARY_KEY_ID` / `NOTARY_ISSUER_ID`) — see
[release-ci.md](release-ci.md).

1. Build, sign, and notarize the app bundle:

   ```sh
   SIGNING_IDENTITY="Slovo Local Development" NOTARY_PROFILE="…" \
     Scripts/sign-and-notarize.sh app
   ```

2. Staple the ticket to the app — manual, on a networked Mac:

   ```sh
   xcrun stapler staple .build/dist/Slovo.app
   ```

3. Package the stapled app into a signed, notarized `Slovo.dmg`:

   ```sh
   SIGNING_IDENTITY="Slovo Local Development" NOTARY_PROFILE="…" \
     Scripts/sign-and-notarize.sh dmg
   ```

4. Staple the ticket to the DMG — manual, on a networked Mac:

   ```sh
   xcrun stapler staple .build/dist/Slovo.dmg
   ```

Confirm both `notarytool` submissions report `Accepted`. Stapling is kept a
separate manual step because it contacts Apple CloudKit and can fail behind a
TLS-inspecting proxy even when notarization succeeds; run it on a network that
does not break Apple certificate pinning. Verify the signed, stapled artifacts:

```sh
codesign --verify --deep --strict --verbose=2 .build/dist/Slovo.app
codesign --verify --verbose=2 .build/dist/Slovo.dmg
spctl --assess --type execute --verbose .build/dist/Slovo.app
xcrun stapler validate .build/dist/Slovo.app
xcrun stapler validate .build/dist/Slovo.dmg
```

## Publish

Upload the stapled DMG to a GitHub release for the tag:

```sh
gh release create vX.Y.Z --title "vX.Y.Z" --notes-file <notes> .build/dist/Slovo.dmg
```

## Manual L4 Checks

- first launch shows setup only when required permissions are missing.
- Microphone and Accessibility prompts or deep links lead to the correct System
  Settings panes.
- Input Monitoring is shown only as targeted hotkey recovery after an event-tap
  startup failure.
- Speech Recognition is declared for compatibility but is not shown as a
  first-run blocker unless the live runtime proves it is required.
- TCC grants survive rebuild when the signing identity is stable.
- The menu-bar icon renders through `NotoSansGlagolitic-Regular`; recording,
  processing, and idle states are visually distinct.
- Holding the configured push-to-talk key (`fn` by default) starts capture,
  releasing it stops capture, restores audio, and inserts text into a normal
  text field.
- Secure-input fields fail closed without writing transcript text to the
  clipboard.
- Offline, refused, unavailable, or misconfigured cleanup falls back to
  `PassThrough` and preserves the user's words.
- The OpenRouter key is read from Keychain lazily when cleanup runs.
- `biasTerms` reach the transcriber path on a real on-device run.
- privacy holds: raw audio stays local, secrets are never logged, cleanup is
  always attempted through OpenRouter, and fallback inserts the direct transcript
  only when cleanup is unavailable, refused, or misconfigured.
