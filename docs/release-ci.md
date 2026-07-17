# Release CI/CD

Slovo releases itself. A push to `main` runs one pipeline
([.github/workflows/release.yml](../.github/workflows/release.yml)) that decides on
its own whether a release is due, computes the next version, builds, signs,
notarizes, staples, tags, and publishes the GitHub Release with the stapled
artifacts. **Nobody runs a release command, edits a version, or pushes a tag by
hand — there is no supported manual path.** Stapling contacts Apple over a clean
network, so CI is also the first place the full signing chain can finish end to
end; local stapling can be blocked by a TLS-inspecting corporate proxy.

## How the pipeline decides

On every push to `main` (and on a manual `workflow_dispatch`) the pipeline inspects
the [Conventional Commits](https://www.conventionalcommits.org/) since the last
`v*` release tag:

- **Something to release** — any `feat` (minor), `fix` / `perf` (patch), or a
  breaking change (`type!:` or a `BREAKING CHANGE:` footer, major). The pipeline
  computes the next semantic version, stamps it, builds the signed app, then
  commits the version bump, tags `v<version>`, and publishes a GitHub Release.
- **Nothing to release** — only `docs`, `chore`, `ci`, and similar. The run is
  trunk verification: it still runs the full test gate and packages a signed
  artifact (under a unique dev stamp), but creates **no** tag and **no** release.

The version number is computed by [`release-it`](https://github.com/release-it/release-it)
in `--ci` mode with the `@release-it/conventional-changelog` plugin
(`preset: conventionalcommits`). release-it's engine on its own would recommend a
patch for *any* non-empty commit set, so a tiny guard,
[`Scripts/release-decision.sh`](../Scripts/release-decision.sh), is the authority
on whether a release is due at all. The guard and release-it agree on the trigger
set, so a docs-only push never cuts a release.

## Trigger matrix

| Trigger | Test gate | Signed + notarized + stapled app & DMG | Uploaded artifact (`slovo-macos`) | Version bump + tag + GitHub Release |
| --- | --- | --- | --- | --- |
| push to `main`, releasable commits | yes | yes (computed version) | yes | **yes** (`v<version>` + DMG & zip) |
| push to `main`, nothing releasable | yes | yes (unique dev stamp) | yes | no |
| `workflow_dispatch` on `main` | yes | yes | yes | yes when releasable |
| `pull_request` into `main` | yes ([swift.yml](../.github/workflows/swift.yml) only) | no | no | no |
| pushing a `v*` tag | — the workflow has no tag trigger; tags are created only by the pipeline | | | |

The test gate is the reusable [swift.yml](../.github/workflows/swift.yml) workflow
(the same one that guards pull requests), so every packaged build is gated by the
full Swift test suite. The pipeline never runs on `pull_request`, so fork code
never sees signing secrets.

## Jobs and least privilege

| Job | Runner | Permissions | Secrets | Does |
| --- | --- | --- | --- | --- |
| `test` | macOS | `contents: read` | none | reusable Swift test gate |
| `decide` | Linux | `contents: read` | none | run the guard, compute the version |
| `package` | macOS | `contents: read`, `environment: release` | signing secrets | stamp version, build, sign, notarize, staple, verify, upload artifact |
| `publish` | macOS | `contents: write` | none (no signing secrets) | stamp + changelog, commit bump, tag, GitHub Release |

Signing secrets live only in the protected `release` environment and are reachable
only from `package`. Write access to the repository is isolated to `publish`,
which holds no signing secrets. This split is deliberate; keep it.

CI bakes in the strict release checks: `codesign --verify --strict --deep`, bundle
identifier `com.slovo.app`, team identifier `ZN8H5SF4R7`, `stapler validate` on
both the app and the DMG, and a Gatekeeper assessment
(`spctl --assess --type execute`).

## Versioning

- **Marketing version** (`CFBundleShortVersionString`): the computed semantic
  version for a release; for a non-release trunk build it is the last released
  version marked `-ci.<run-number>` so a dev artifact never masquerades as a
  release.
- **Build number** (`CFBundleVersion`): `git rev-list --count HEAD` for a release
  — deterministic and monotonic — and the unique CI run number for a dev build.
- The version is stamped into `Resources/Info.plist` on the runner at build time
  by [`Scripts/stamp-app-version.sh`](../Scripts/stamp-app-version.sh); the
  `package` and `publish` jobs call it with identical arguments so the signed
  artifact and the committed plist agree.
- The committed `CFBundleVersion` records the build number of the packaged commit.
  The release-bookkeeping commit adds one more commit, so a later
  `git rev-list --count` from the tag reads one higher — expected, and still
  strictly monotonic across releases.

## Why one run does everything (no PAT, no double-fire)

The `publish` job pushes the version-bump commit and the tag with the built-in
`GITHUB_TOKEN`. GitHub deliberately does **not** start a new workflow run from
events triggered by `GITHUB_TOKEN` (loop protection), and the bump commit also
carries `[skip ci]`. That is why the whole release finishes in the single run that
a human's push started, with no personal access token and no second, tag-triggered
run. The workflow has no `tags: v*` trigger at all — tags are created only by this
pipeline — so a tag push can never spawn a duplicate packaging run.

## Changelog

`CHANGELOG.md` stays in its [Keep a Changelog](https://keepachangelog.com/) style.
On a release the `publish` job promotes the top `## [Unreleased]` heading to
`## [<version>] - <date>` and opens a fresh empty `## [Unreleased]`
([`Scripts/promote-changelog.sh`](../Scripts/promote-changelog.sh)). Contributors
may curate `## [Unreleased]` between releases; the authoritative per-release notes
are the GitHub Release body, generated from the commits.

## Node tooling

`release-it` is dev-only tooling, pinned exactly in `package.json` with a committed
`package-lock.json`; `node_modules` is gitignored and never committed. The app is
Swift and this package is never published to npm. In CI the secret-less `decide`
job runs `npm ci --ignore-scripts` and then `npx --no-install release-it` against
the lockfile-installed binary, so the exact pinned versions run and no dependency
lifecycle script executes.

`.release-it.json` runs release-it in compute-only mode: every mutating action is
disabled (`git.commit` / `git.tag` / `git.push` / `npm.publish` / `github.release`
all `false`), and it is invoked only as `--release-version`, so it just prints the
next version. The `tagName: "v${version}"` entry declares the project's tag
convention so release-it parses the `v`-prefixed tags as the version anchor; the
workflow — not release-it — creates the tag.

The guard's release-trigger set (`feat` / `fix` / `perf` / breaking) is kept in
agreement with the pinned `conventionalcommits` preset by exact version pinning. If
you ever upgrade `@release-it/conventional-changelog`, re-verify that its bump types
still match `Scripts/release-decision.sh` so the guard and the computed version do
not drift.

## One-time owner setup

Done once by the repository owner in the browser and a local terminal. Nothing here
is committed to the repository.

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

In **Settings → Environments**, create an environment named `release`. Add the five
secrets below as **environment** secrets (not repository secrets), so only the
packaging job can read them.

| Secret name | Value |
| --- | --- |
| `DEVELOPER_ID_APP_P12_BASE64` | base64 of the Developer ID `.p12` (step 1) |
| `DEVELOPER_ID_APP_P12_PASSWORD` | the `.p12` export password (step 1) |
| `ASC_API_KEY_P8_BASE64` | base64 of the App Store Connect `.p8` (step 2) |
| `ASC_API_KEY_ID` | the App Store Connect Key ID (step 2) |
| `ASC_API_ISSUER_ID` | the App Store Connect Issuer ID (step 2) |

If you add a **deployment branch/tag** rule to the `release` environment, it must
allow `main` — the packaging job runs on every push to `main`, not only on tags.

### Branch protection nuance

The pipeline works today because `main` is not protected. If you enable branch
protection on `main`, the `publish` job's push of the version-bump commit will be
rejected unless the rule lets the automation through. Either allow the
`github-actions[bot]` actor (or the `GITHUB_TOKEN`) to bypass the pull-request
requirement, or exempt it from the push restriction. Without that, releases will
package artifacts but fail at the commit/tag step.

## What you observe

- **A releasable push:** a new tag `v<version>` and a GitHub Release appear with
  `Slovo.dmg` and `Slovo.zip` attached and generated notes; the `README.md` install
  link and Release badge point at the latest release, so a published release is
  immediately what users download.
- **A non-releasable push:** open the run and download the `slovo-macos` artifact
  from the run summary. Unzip it, mount `Slovo.dmg`, drag **Slovo** to Applications,
  and launch it. A stapled build opens with no Gatekeeper network round-trip.

If the first notarization submission fails with an authentication error, confirm
the App Store Connect key uses the **Admin** role and that
`ASC_API_KEY_ID`/`ASC_API_ISSUER_ID` match the downloaded key.

## Local packaging for verification

Local, manual packaging still exists only to **verify a build before it is merged**,
never to cut a release — see [release-checklist.md](release-checklist.md). The
signing script accepts either credential source: `NOTARY_PROFILE` locally, or the
App Store Connect API key (`NOTARY_KEY_P8` / `NOTARY_KEY_ID` / `NOTARY_ISSUER_ID`)
in CI.
