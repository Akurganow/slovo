# Release CI/CD

Slovo builds, signs, notarizes, staples, and publishes the distributable app
automatically on GitHub-hosted macOS runners
([.github/workflows/release.yml](../.github/workflows/release.yml)). Stapling
contacts Apple over a clean network, so CI is the first place the full chain can
finish end to end; local stapling can be blocked by a TLS-inspecting corporate
proxy.

This runbook is the one-time owner setup plus the day-to-day trigger and verify
flow. It requires no code changes — only repository secrets and an environment.

## What the pipeline does

The `Release` workflow runs on push to `main`, on `v*` tags, and on manual
`workflow_dispatch`. It never runs on pull requests, so fork code never sees
signing secrets.

| Trigger | Tests | Signed + notarized + stapled app & DMG | Uploaded as workflow artifact | GitHub Release |
| --- | --- | --- | --- | --- |
| `workflow_dispatch` | yes | yes | yes (`slovo-macos`) | no |
| push to `main` | yes | yes | yes (`slovo-macos`) | no |
| push `v*` tag | yes | yes | yes (`slovo-macos`) | yes (DMG + app zip) |

The test gate is the reusable [swift.yml](../.github/workflows/swift.yml) workflow
(the same one that guards pull requests), so every packaged build is gated by the
full Swift test suite.

CI bakes in the strict release checks: `codesign --verify --strict --deep`,
bundle identifier `com.slovo.app`, team identifier `ZN8H5SF4R7`,
`stapler validate` on both the app and the DMG, and a Gatekeeper assessment
(`spctl --assess --type execute`).

## One-time setup

All of this is done once by the repository owner in the browser and a local
terminal. Nothing here is committed to the repository.

### 1. Export the Developer ID signing certificate

Export the **Developer ID Application: Alexander Kurganov (ZN8H5SF4R7)** identity
(certificate **and** private key) from Keychain Access as a `.p12`, choosing a
strong export password. Then base64-encode it for GitHub:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy   # -> DEVELOPER_ID_APP_P12_BASE64
```

Keep the export password for the `DEVELOPER_ID_APP_P12_PASSWORD` secret.

### 2. Create an App Store Connect API key for notarization

In [App Store Connect → Users and Access → Integrations → App Store Connect
API](https://appstoreconnect.apple.com/access/integrations/api), create a key.
Use the **Admin** role: the minimal *Developer* role can fail notarization
submissions. Download the `.p8` once (it cannot be re-downloaded) and note the
**Key ID** and the team **Issuer ID** shown on that page. Then base64-encode the
key:

```sh
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy        # -> ASC_API_KEY_P8_BASE64
```

Notarization uses the App Store Connect API key (`--key/--key-id/--issuer`), not
an Apple ID and app-specific password.

### 3. Create the `release` environment and secrets

In **Settings → Environments**, create an environment named `release`. Add the
five secrets below as **environment** secrets (not repository secrets), so only
the packaging job — which runs only on push/tag/dispatch — can read them.

| Secret name | Value |
| --- | --- |
| `DEVELOPER_ID_APP_P12_BASE64` | base64 of the Developer ID `.p12` (step 1) |
| `DEVELOPER_ID_APP_P12_PASSWORD` | the `.p12` export password (step 1) |
| `ASC_API_KEY_P8_BASE64` | base64 of the App Store Connect `.p8` (step 2) |
| `ASC_API_KEY_ID` | the App Store Connect Key ID (step 2) |
| `ASC_API_ISSUER_ID` | the App Store Connect Issuer ID (step 2) |

Recommended, optional hardening (owner clicks; the workflow does not require it):

- On the `release` environment, add a **deployment branch and tag** rule limiting
  it to `main` and `v*` so the environment's secrets are only usable from those
  refs.
- Enable branch protection on `main`.

## First run: verify the artifact

1. Go to **Actions → Release → Run workflow** and run it on `main`
   (`workflow_dispatch`). A push to `main` triggers the same path.
2. When the run finishes, open it and download the `slovo-macos` artifact from the
   run summary.
3. Unzip it, mount `Slovo.dmg`, drag **Slovo** to Applications, and launch it. A
   stapled build opens with no Gatekeeper network round-trip.

If the first notarization submission fails with an authentication error, confirm
the App Store Connect key uses the **Admin** role and that
`ASC_API_KEY_ID`/`ASC_API_ISSUER_ID` match the downloaded key.

## Cutting a release

Push a version tag; the pipeline tests, packages, staples, and publishes a GitHub
Release with the stapled `Slovo.dmg` and `Slovo.zip` attached, with generated
notes:

```sh
git tag v0.9.0
git push origin v0.9.0
```

The tag name becomes the release title. The `README.md` install link and Release
badge point at the latest release, so a published tag is immediately what users
download.

## Local packaging still works

Local, manual packaging is unchanged and still uses a `notarytool` keychain
profile — see [release-checklist.md](release-checklist.md). The signing script
accepts either credential source: `NOTARY_PROFILE` locally, or the App Store
Connect API key (`NOTARY_KEY_P8` / `NOTARY_KEY_ID` / `NOTARY_ISSUER_ID`) in CI.
