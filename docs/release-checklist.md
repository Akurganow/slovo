# Release Checklist

Releases are fully automated. A push to `main` runs the pipeline in
[release-ci.md](release-ci.md), which decides whether a release is due, computes
the version, builds, signs, notarizes, staples, tags, and publishes the GitHub
Release. **You never cut a release by hand — no manual version edit, no manual tag,
no `gh release create`.** This checklist is what to verify *before* your change is
merged to `main`, so that the automated release it may trigger is sound.

## Automated gate

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

## Conventional commits drive the release

The pipeline computes the next version from the Conventional Commits since the last
`v*` tag, so the type prefix on your commits is what decides the bump:

- `feat:` → minor, `fix:` / `perf:` → patch, `type!:` or a `BREAKING CHANGE:`
  footer → major.
- `docs:`, `chore:`, `ci:`, `refactor:`, `test:`, `style:`, `build:` → no release
  on their own; the push is verified and packaged but not released.

Optionally curate `## [Unreleased]` in `CHANGELOG.md`; on release the pipeline
promotes it to the new version section and the GitHub Release notes are generated
from the commits.

## Verify packaging before merge (optional, local)

The signed-packaging chain only fully finishes in CI (stapling needs a clean
network), but you can verify signing locally before merging a change that touches
packaging. This never releases anything — it only produces local artifacts.

Use a stable Developer ID identity; ad-hoc signing cannot prove that TCC grants
survive a rebuild. Set `NOTARY_PROFILE` (a `notarytool` keychain profile) to
notarize locally; without it a phase stops after signing.

1. Build, sign, and notarize the app bundle:

   ```sh
   SIGNING_IDENTITY="Developer ID Application: Alexander Kurganov (ZN8H5SF4R7)" \
     NOTARY_PROFILE="…" Scripts/sign-and-notarize.sh app
   ```

2. Staple the ticket to the app — on a networked Mac:

   ```sh
   xcrun stapler staple .build/dist/Slovo.app
   ```

3. Package the stapled app into a signed, notarized `Slovo.dmg`:

   ```sh
   SIGNING_IDENTITY="Developer ID Application: Alexander Kurganov (ZN8H5SF4R7)" \
     NOTARY_PROFILE="…" Scripts/sign-and-notarize.sh dmg
   ```

4. Staple the ticket to the DMG — on a networked Mac:

   ```sh
   xcrun stapler staple .build/dist/Slovo.dmg
   ```

Confirm both `notarytool` submissions report `Accepted`, then verify the signed,
stapled artifacts:

```sh
codesign --verify --deep --strict --verbose=2 .build/dist/Slovo.app
codesign --verify --verbose=2 .build/dist/Slovo.dmg
spctl --assess --type execute --verbose .build/dist/Slovo.app
xcrun stapler validate .build/dist/Slovo.app
xcrun stapler validate .build/dist/Slovo.dmg
```

## Manual L4 checks

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
