# Release CI/CD

Slovo releases itself. A push to `main` runs one pipeline
([.github/workflows/release.yml](../.github/workflows/release.yml)) that decides on
its own whether a release is due, computes the next version, builds, signs,
notarizes, staples, tags, and publishes the GitHub Release with the stapled
artifacts. **Nobody edits a version or pushes a tag by hand.** A person runs the
pipeline in two ways: dispatch it on `main`, which decides as a push does, or re-run
a failed `publish` job ([When `publish` fails](#when-publish-fails)).
Stapling contacts Apple over the network, and CI runs the full signing chain end
to end.

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

Both the decision and the version number come from one
[`git-cliff`](https://git-cliff.org) run, configured by [`cliff.toml`](../cliff.toml)
(see [Version computation](#version-computation)). It reports the bump it would
make — `major`, `minor`, `patch`, or none — and the resulting version; a push
whose commits move nothing is trunk verification.

Pull requests land on `main` as squash merges, so the merged commit's
header is what git-cliff classifies. GitHub pre-fills that header from the
pull request's title. On a one-commit branch it pre-fills from the commit's
own message instead. A merged header without `feat:` / `fix:` / `perf:`
releases nothing: the push runs trunk verification. PR #77 lost a release
this way — a one-commit branch whose commit carried `docs:`.

## Trigger matrix

| Trigger | Test gate | Signed + notarized + stapled app & DMG | Uploaded artifact (`slovo-macos`) | Version bump + tag + GitHub Release |
| --- | --- | --- | --- | --- |
| push to `main`, releasable commits | yes | yes (computed version) | yes | **yes** (`v<version>` + DMG & zip) |
| push to `main`, nothing releasable | yes | yes (unique dev stamp) | yes | no |
| `workflow_dispatch` on `main` | yes | yes | yes | yes when releasable |
| `pull_request` into `main` | yes ([swift.yml](../.github/workflows/swift.yml) only) | no | no | no |
| pushing a `v*` tag | — the workflow has no tag trigger; tags are created only by the pipeline | | | |
| `workflow_dispatch` of [dev-build.yml](../.github/workflows/dev-build.yml) on any branch, or labeling a PR `dev-build` | yes | signed app & DMG — no notarization, no staple | yes (`slovo-dev`, 7-day retention) | no |

A release that changes a file that can change the cleanup output, and a manual
dispatch on `main`, also start the [cleanup benchmark](#cleanup-benchmark), a workflow
of its own.

The test gate is the reusable [swift.yml](../.github/workflows/swift.yml) workflow,
the same one that guards pull requests. What the gate runs, and how CI uses it, is
in [docs/development.md](development.md), "Full Gate". The pipeline never runs on
`pull_request`, so fork code never sees signing secrets.

## Jobs and least privilege

| Job | Runner | Permissions | Secrets | Does |
| --- | --- | --- | --- | --- |
| `test` | macOS | `contents: read` | none | reusable gate (`Scripts/diagnose.sh`) |
| `decide` | Linux | `contents: read` | none | run git-cliff: is a release due, and at which version |
| `package` | macOS | `contents: read`, `environment: release` | signing secrets, and the Sparkle EdDSA key `SPARKLE_ED_PRIVATE_KEY` | stamp version, import the signing certificate into an ephemeral keychain ([`Scripts/import-signing-certificate.sh`](../Scripts/import-signing-certificate.sh)), build, sign, notarize, staple, verify, generate the Sparkle appcast, upload artifact |
| `publish` | macOS | `contents: write`, `environment: release-push` | the push deploy key only (no signing secrets) | stamp + changelog, commit bump, tag, GitHub Release |

Signing secrets live only in the protected `release` environment and are reachable
only from `package`. Write access to the repository is isolated to `publish` and to
the `record` job of the [cleanup benchmark](#cleanup-benchmark), and neither holds
signing secrets. The deploy key that pushes the version bump lives alone in the
`release-push` environment and is reachable only from those two jobs. This split is
deliberate; keep it.

CI bakes in the strict release checks: `codesign --verify --strict --deep`, bundle
identifier `com.slovo.app`, team identifier `ZN8H5SF4R7`, `stapler validate` on
both the app and the DMG, and a Gatekeeper assessment
(`spctl --assess --type execute`).

Every job that runs steps sets `timeout-minutes` in its workflow file. A job that calls
the reusable gate has no steps of its own, so the called job in
[swift.yml](../.github/workflows/swift.yml) sets the timeout.

Every outside action in the workflows is pinned to a full commit SHA, with its version
in a trailing comment such as `# v2.90.3`. GitHub's security guide,
[Using third-party actions](https://docs.github.com/en/actions/reference/security/secure-use#using-third-party-actions)
(`github/docs` revision `ecafe7144a016cab7a88e3e77437f38ce1a4ee73`), advises a commit
SHA, and a tag only for creators one trusts, because a tag can be moved or deleted if a
bad actor gains access to the repository storing the action. Renovate, configured
in [`renovate.json`](../renovate.json), opens the update pull requests for these
pins and for the Swift packages. Its `github-actions` manager updates a pinned
commit SHA to follow the version tag in the trailing comment (Renovate's
documentation, `lib/modules/manager/github-actions/readme.md`, "Digest pinning and
updating", tag `44.257.9`). `minimumReleaseAge` holds each new version for 7 days
after its release, and a security update skips that wait (Renovate's documentation,
`docs/usage/key-concepts/minimum-release-age.md`, "What happens to security
updates?", tag `44.257.9`).

Two limits of that setup, both read in Renovate's source at tag `44.257.9`:

- **The release date comes from git.** Every dependency here resolves through
  `github-tags`. It takes the commit date for a lightweight tag and the tagger
  date for an annotated one (`lib/util/github/graphql/query-adapters/tags-query-adapter.ts`).
  Whoever makes the tag sets both dates, so a backdated tag passes the 7-day hold
  at once. Switching to `github-releases` would close this hole and stop other
  updates. `github/codeql-action` and `sindresorhus/Settings` publish their
  versions as tags without a GitHub Release, so their updates would no longer
  arrive.
- **Only the updated package's pin moves.** For a Swift update, Renovate rewrites
  that package's version and revision in `Package.resolved` and runs no resolution
  (`lib/modules/manager/swift/artifacts.ts`, `updatePinInJson`). A new version
  that needs a newer transitive package fails the gate, which builds with
  `--disable-automatic-resolution`. Fix such a pull request with
  `swift package resolve` on its branch.

## Dev builds on demand

[dev-build.yml](../.github/workflows/dev-build.yml) exists for one consumer: the
owner, testing a branch by hand on a Mac that cannot build or sign it locally,
or after a cloud coding session that pushed a branch from a Linux container. It
is **not** a distribution channel.

- **Triggers:** two, producing the same artifact. (1) Manual `workflow_dispatch`
  on a chosen branch — only accounts with write access can dispatch it. (2) The
  in-PR "button": apply the `dev-build` label to a pull request (one click in
  the PR sidebar; labels require triage rights or higher, so only the owner and
  invited collaborators can click). A label run builds the PR's **merge
  result** — the code as it would land on `main` — appears in the PR's checks,
  posts one sticky PR comment linking the finished DMG (updated in place on
  rebuilds), and removes the label so the next click starts a fresh build.
  Fork code can neither trigger the workflow nor read its secrets; either
  trigger is the owner's approval of the code being signed.
- **What it does:** run the full reusable test gate, stamp a run-scoped dev
  version (`<last-release>-dev.<run-number>` — the same never-masquerade idiom
  as the trunk `-ci.N` stamp), import the Developer ID certificate with the same
  script as `package`, build, sign the app and a DMG with the stable
  Developer ID, verify the signatures, and upload the DMG as a `slovo-dev`
  artifact with 7-day retention.
- **Permissions of the comment job:** `announce` holds only `pull-requests: write`.
  The REST reference lists the "Pull requests" repository permission as an accepted
  permission set for each of its four calls (list, create and update an issue
  comment; remove a label from an issue), at `write`, or `read` for the list,
  and marks each as available to installation tokens such as the `GITHUB_TOKEN`
  (`serverToServer: true`; `github/docs` revision
  `5857578e1688ae994c2f2062266414e3583cdf55`,
  `src/rest/data/fpt-2022-11-28/issues.json`, the data behind the pages
  [Issue comments](https://docs.github.com/en/rest/issues/comments) and
  [Labels](https://docs.github.com/en/rest/issues/labels)). The same pages require
  "at least one of the following permission sets" (`data/ui.yml`, revision
  `1036ae83e445f8c725b5e01a1f34df036db87dfb`).
- **Concurrency:** a newer dev build for the same ref and label cancels one still
  running; a run started by another label does not cancel it
  ([dev-build.yml](../.github/workflows/dev-build.yml), `concurrency` block).
- **What it deliberately cannot do:** notarize, staple, tag, or release. The
  `dev-signing` environment holds only the two certificate secrets
  — no App Store Connect key, no Sparkle key — so even a dispatched run cannot
  produce a notarized artifact or touch the update feed.
- **Using the artifact:** the run-summary download is `slovo-dev.zip` — GitHub
  wraps every artifact in its own zip, and that wrapper is lossy (symlinks and
  exec bits are dropped, fatal for the embedded Sparkle.framework), which is
  why a lossless signed `Slovo.dmg` rides inside rather than a bare `.app`.
  Unzip once — if Archive Utility rejects the streaming zip, run
  `ditto -x -k slovo-dev.zip .` in Terminal — then double-click the DMG and
  drag **Slovo** to Applications. The first launch of an unnotarized build needs the one-time
  Gatekeeper bypass (System Settings → Privacy & Security → **Open Anyway**);
  that friction is accepted for a dev build. Because the signing identity is
  the same Developer ID as releases and local dev builds, macOS privacy grants
  (microphone, Accessibility, Input Monitoring) stay stable across all of them.

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

The `publish` job pushes the version-bump commit and the tag in one
`git push --atomic`, over SSH, with a write-access deploy key, `RELEASE_DEPLOY_KEY`.
git v2.56.1 (commit `03b41523c576f26ad34085378717a0c1b287470f`,
`Documentation/git-push.adoc`, lines 205-209) documents the atomic guarantee: either
all refs are updated, or on error no refs are updated. The same text says the push
fails when the server does not support atomic pushes. The `main` ruleset requires a
pull request, and deploy keys are on its bypass list. The built-in `GITHUB_TOKEN`
pushes as the GitHub Actions app, which the ruleset does not list. `gh release
create` still uses the `GITHUB_TOKEN`, since creating a release is not a branch
push.
`publish` installs git-cliff before the keyed checkout, so no action from
outside GitHub runs while the key is on disk.

A deploy-key push starts workflow runs. GitHub's loop protection covers only
events the `GITHUB_TOKEN` triggers
([GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token)).
Two facts keep the release push, which carries both refs, from starting any workflow run:

- **The bump commit.** Two workflows trigger on a push to `main`: `release.yml`
  and [codeql.yml](../.github/workflows/codeql.yml). The commit carries
  `[skip ci]`, which skips every `push` and `pull_request` run its own push would
  start
  ([Skipping workflow runs](https://docs.github.com/en/actions/how-tos/managing-workflow-runs-and-deployments/managing-workflow-runs/skipping-workflow-runs)).
  It is the only commit in that push. A `main` that moved meanwhile rejects the
  whole push, tag included, as non-fast-forward.
- **The `v<version>` tag.** Both workflows filter `push` by branch only, and such
  a workflow never runs for a tag push
  ([Workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)).
  No workflow triggers on `tags`, `create`, or `release`.

That is why the whole release finishes in the single run that a human's push
started, with no personal access token and no second, tag-triggered run. A
workflow that later triggers on tags or on `create` starts on every release.

## When `publish` fails

Finish a failed release with **Re-run failed jobs** on that run, within 30 days of
the run (GitHub docs, [Re-running workflows and jobs](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs),
`github/docs` revision `6abed3d818a57eeb80b1a9275b96a5446cb16d23`). The page says a
re-run uses the run's commit and ref, and that re-running failed jobs also re-runs the
jobs that depend on them while the other jobs keep their outputs. Do not choose
**Re-run all jobs**. It re-runs `package`, which already succeeded, and that job's
upload of `slovo-macos` fails if an artifact of that name already exists:
`actions/upload-artifact` v7.0.2 (commit `cf430e030ddbb5b0abf93d22962f4752f3646cd9`),
`README.md` line 101, says: "If false, the action will fail if an artifact for the given
name already exists." The workflow does not set `overwrite`, so the default `'false'`
applies (`README.md` line 103).

A `package` that failed or timed out before its upload step is finished the same way,
because the upload is its last step and the only one that creates `slovo-macos`; a
failure inside the upload step is not covered.

The step "Bump, tag, and push the release unless its tag exists" in
[release.yml](../.github/workflows/release.yml) does nothing when `v<version>` already
exists on a commit whose parent is the one packaged. The `Publish GitHub Release` step
passes `--latest` only when `v<version>` is the highest `v[0-9]*` tag by version order
(`git tag --list 'v[0-9]*' --sort=-version:refname`). Otherwise it passes
`--latest=false`. The flag marks the release as Latest, and `--latest=false` keeps it
from being Latest (`gh` flag help, `cli/cli` v2.103.3,
`pkg/cmd/release/create/create.go:221`).

When `v<version>` is already published, a re-run fails at `gh release create` with
"a release with the same tag name already exists" (`cli/cli` v2.103.3,
`pkg/cmd/release/create/create.go:503-511`, which runs for a call with assets and no
`--draft`). Nothing is left to do.

A run cancelled, timed out, or lost to its runner during `gh release create` can leave a
draft release with the tag. With assets, `gh` creates the release as a draft first and
deletes that draft only when one of its calls returns an error (`cli/cli` v2.103.3,
`pkg/cmd/release/create/create.go:512-514` and `:536-566`). Its existence check looks
at published releases (`publishedReleaseExists`,
`pkg/cmd/release/create/http.go:110-138`). Delete the leftover draft on the Releases
page.

A re-run does not fix these failures:

- **A push refused because `main` moved.** The re-run checks out the old commit and
  is refused again. The next push to `main` starts a run that decides again and
  releases.
- **The tag `v<version>` exists, but its parent is not the commit this run packaged.**
  The bump step fails on purpose, before it stamps, commits or pushes. A re-run fails
  the same way, since it packages the same commit. The pipeline does not move or
  delete tags.

A push refused for another reason, such as a missing deploy key, is fixed by a re-run
once the key works, as long as `main` has not moved. See
[The `main` ruleset](#the-main-ruleset).

By default, a run queued while another run of the group is in progress is `pending`,
and a newly queued run cancels the existing pending run and takes its place (GitHub docs,
[Control the concurrency of workflows and jobs](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency),
`data/reusables/actions/actions-group-concurrency.md`, included through
`data/reusables/actions/jobs/section-using-concurrency-jobs.md`, `github/docs`
revision `336b7f546d9443dab4e1fa4f0f470e45448c7abc`). If a pending release run was
cancelled, dispatch the pipeline on `main`. It decides again over every commit since the
last tag.

## Cleanup benchmark

[cleanup-benchmark.yml](../.github/workflows/cleanup-benchmark.yml) runs the cleanup
benchmark over every catalogue model, with the judge, against the entries in
[`Benchmarks/cleanup/baseline.json`](../Benchmarks/cleanup/baseline.json). Every run
makes paid requests for every model. It is a workflow of its own: the Release run
neither waits for it nor depends on it.

**When it runs.**

- After a Release run completes on `main` (a `workflow_run` trigger), only when that
  run concluded `success`, published a release, and the release changed a file that can
  change the cleanup output. A Release run whose publish failed after its tag has the
  tag too, so only the success of its re-run starts the benchmark. The run published
  a release when a `v*` tag has the Release run's commit as its parent, the test
  `publish` applies before it tags. The files are compared with
  the previous release tag. The workflow's `changes` job holds the list of files, and
  that is the one place it is written.
- By `workflow_dispatch` on `main`, with no inputs and no file check. A dispatch on
  another ref does nothing.

GitHub's documentation says a `workflow_run` run "is able to access secrets and write
tokens", and that the trigger needs the workflow file on the default branch
([Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows),
`github/docs` revision `801373e82d10ab6b9a62b01aea68edc2ecdf633a`,
`content/actions/reference/workflows-and-actions/events-that-trigger-workflows.md`,
"workflow_run"). Only the `requested` activity type "does not occur when a workflow is
re-run" (same page), so a re-run of a Release run that already published fires
`completed` again and pays again.

**The jobs.** `changes` holds nothing and decides whether to run. `benchmark` runs on
macOS, holds the OpenRouter key and nothing else, and uploads the artifact. `record`
runs in the `release-push` environment with the deploy key and a token with
`contents: write` and `pull-requests: write`. The two keys never share a job.

**The artifact.** `cleanup-baseline` holds `baseline.json`, the baseline with fresh
entries, `report.csv`, the aggregate report, and `failed-rows.tsv`, the verdict rows
that failed. It is kept for seven days and is uploaded even after a red step.

**What a run does.** The tool's exit code decides.

- **No degradation.** `record` commits the artifact's `baseline.json` to `main` as
  `github-actions[bot]`, headed `chore(benchmark): record the cleanup baseline for
  v<version>` (a dispatch names the short commit id). The push uses the deploy
  key that `publish` uses. The header is not releasable and carries no skip token, so the push
  runs trunk verification and releases nothing, and its own `workflow_run` finds no
  release and stops. A model with no entry of its own is judged against
  `gpt-6-luna`'s entry, and a failure there is a warning annotation, not a
  degradation, so the model's first entry is recorded. The job commits only while
  `main` still points at the commit the run started from: the bump commit that the
  release tag points at, or the dispatched commit. If `main` has moved, the job warns
  and commits nothing, and the next release records the baseline. A push to `main`
  while a newer Release run is still packaging makes that run's bump push
  non-fast-forward, so its publish is refused. A moved `main` is when such a run can
  exist.
- **A degradation.** A model failed the bar against its own entry. Nothing is
  committed and the artifact stays. The release note gains a section, "Cleanup
  benchmark: degradation", listing each such model and category with its misses
  against the allowed misses. A dispatch has no release, so the same text goes to
  the run summary. To accept the degradation, a person opens a pull request with the
  `baseline.json` of the run's `cleanup-baseline` artifact. The command wrote that
  file, so the change is not a hand edit.
- **A stale baseline.** An entry was recorded on another dataset file, judge
  settings, bar scheme or style. The tool refuses before any request. The job runs
  it again without a baseline to record new entries, pushes them on a branch
  `benchmark/baseline-<release or short commit id>-<run id>-<run attempt>`, and opens
  a pull request into `main` headed `chore(benchmark): re-record the cleanup baseline for
  <release or short commit id>`. The release note gains a section, "Cleanup
  benchmark: stale baseline", that links the pull request.

The stale-baseline pull request needs two acts by a person with admin or write
access, and no workflow does either:

1. Before the first stale run, turn on the repository setting **Allow GitHub Actions
   to create and approve pull requests** (Settings → Actions → General → Workflow
   permissions). `GITHUB_TOKEN` creates a pull request only while it is on
   ([Managing GitHub Actions settings for a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository),
   `github/docs` revision `801373e82d10ab6b9a62b01aea68edc2ecdf633a`, "Workflow
   permissions").
2. On each such pull request, select **Approve workflows to run**. A pull request
   that `GITHUB_TOKEN` creates starts its workflow runs in an approval-required state
   (`github/docs` revision `801373e82d10ab6b9a62b01aea68edc2ecdf633a`,
   `data/reusables/actions/actions-do-not-trigger-workflows.md`). The first such pull
   request confirms this behaviour, because it is gated by a feature flag in that
   revision.

**Red and green.** A real error turns the run red, and so does a failed push or a
failed release-note edit. The exit codes in
[`Benchmarks/cleanup/README.md`](../Benchmarks/cleanup/README.md) say which exits are
errors. A degradation or a stale baseline ends the run green, with a warning in the
release notes. A red run leaves the release as it shipped, and the gate is still the
`test` job of the Release run.

**Re-running.** "Re-run" on a run of this workflow is a paid run of the whole
catalogue. The artifact upload sets `overwrite`, so the second run replaces the first
run's artifact (see [When `publish` fails](#when-publish-fails) for why the default
fails). A re-run that finds its release note already written adds nothing, and its
stale-baseline branch carries the run attempt, so it does not reuse the first
attempt's branch.

## Changelog

`CHANGELOG.md` stays in its [Keep a Changelog](https://keepachangelog.com/) style
and is written by the pipeline, never by hand. On a release the `publish` job runs
`git-cliff --unreleased --tag v<version> --prepend CHANGELOG.md`, which inserts
`## [<version>] - <date>` under the file's header with one entry per `feat`
(Added), `fix` (Fixed) and `perf` (Changed) commit since the last tag — the same
commits that decided the version. A breaking change is marked **Breaking** in its
type's section, or under Changed for any other type. The entry is the squash
commit's description: the pull request's title after `type(scope): `, or the
commit's own message on a one-commit branch.

The file's header must stay identical to `[changelog] header` in
[`cliff.toml`](../cliff.toml): `--prepend` finds the header by exact text, and a
header that no longer matches is written a second time. `ChangelogHeaderTests`
fails a pull request that lets the two drift.

Sections from 0.10.0 to 0.32.1 were filled once from history with the same
rules; 0.9.0 and older were written by hand and are kept as they are. The GitHub
Release body is GitHub's own generated notes, which list every merged pull
request, docs and dependency updates included.

## Version computation

The `decide` job installs one pinned `git-cliff` binary through
[`taiki-e/install-action`](https://github.com/taiki-e/install-action). A full
commit SHA pins the action's own code, and the action checks the git-cliff
archive's SHA-256. The job then runs `git-cliff --bump --context`. The first
entry of that JSON is the unreleased range when something bumps — carrying
the next version and a `bump_type` of `major`, `minor` or `patch` — or the
last tag itself with `bump_type` null. The job publishes both fields;
`releasable` is "`bump_type` is one of `major`, `minor`, `patch`" and needs no
second opinion.

[`cliff.toml`](../cliff.toml) is the whole rule set:

- `filter_unconventional` drops headers that are not Conventional Commits, such
  as merge commits;
- `commit_parsers` keep `feat`, `fix` and `perf`, keep a `type!:` header or a
  `BREAKING CHANGE:` footer under any conventional type, and skip every other
  commit, known type or unknown;
- `features_always_bump_minor` and `breaking_always_bump_major` fix the increments
  at minor and major, also while the version is still 0.x.

git-cliff reports the version with the tag's `v` prefix; the job strips it, since
the stamp script and the bump step each add their own.

The pin is exact — one `GIT_CLIFF` value at the top of the workflow, used by both
`decide` and `publish` — and outside the update bot's reach: a new git-cliff may
read a header or render the changelog differently. Before moving it, replay both
against the released history. For each pipeline-era tag, run
`git-cliff --bumped-version` at the commit before the tag and expect that tag.
Then add a `fix:` commit after the last tag, run the `publish` job's
`--prepend` command, and expect exactly one new section under the header. At the
pin above, the version replay reproduced 35 of 35 releases, v0.10.0 to v0.32.1.

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

In **Settings → Environments**, create an environment named `release`. Add the six
secrets below as **environment** secrets (not repository secrets), so only the
packaging job can read them.

| Secret name | Value |
| --- | --- |
| `DEVELOPER_ID_APP_P12_BASE64` | base64 of the Developer ID `.p12` (step 1) |
| `DEVELOPER_ID_APP_P12_PASSWORD` | the `.p12` export password (step 1) |
| `ASC_API_KEY_P8_BASE64` | base64 of the App Store Connect `.p8` (step 2) |
| `ASC_API_KEY_ID` | the App Store Connect Key ID (step 2) |
| `ASC_API_ISSUER_ID` | the App Store Connect Issuer ID (step 2) |
| `SPARKLE_ED_PRIVATE_KEY` | the Sparkle EdDSA private key that signs the appcast feed |

Restrict the `release` environment to **Deployment branches → Selected
branches → `main`** (the packaging job runs on every push to `main`, not only on
tags, so `main` must be allowed). This rule is what stops a manual
`workflow_dispatch` of the release pipeline on a side branch from reaching the
signing secrets — and, if the commits qualified, pushing a version bump and tag
from that branch.

### 4. Create the `dev-signing` environment and secrets

In **Settings → Environments**, create an environment named `dev-signing` for
[dev builds on demand](#dev-builds-on-demand). Add the two Developer ID secrets
from step 1 as **environment** secrets — the same values already in `release`
(GitHub cannot share secrets between environments, so paste them again):

| Secret name | Value |
| --- | --- |
| `DEVELOPER_ID_APP_P12_BASE64` | base64 of the Developer ID `.p12` (step 1) |
| `DEVELOPER_ID_APP_P12_PASSWORD` | the `.p12` export password (step 1) |

No other secrets belong here — keeping the notarization and Sparkle keys out of
this environment is what caps what a dev build can do. Leave deployment branches
unrestricted (dev builds are dispatched on arbitrary branches) and add no
required reviewers: the dispatcher is the owner, so a second approval click
would gate nothing.

Also create the PR-trigger label once, in **Issues → Labels → New label**:
name `dev-build` (color and description free). Applying it to a pull request is
the one-click dev-build trigger described in
[Dev builds on demand](#dev-builds-on-demand).

### 5. Create the `release-push` environment and its deploy key

The `publish` job pushes the version bump as a deploy key, the pusher the `main`
ruleset lets past its pull-request rule (see [The `main` ruleset](#the-main-ruleset)).

1. In a local terminal, create a key pair with no passphrase:
   `ssh-keygen -t ed25519 -N "" -C "slovo release push" -f slovo_release_push`
2. In **Settings → Deploy keys → Add deploy key**, paste `slovo_release_push.pub`.
3. Tick **Allow write access** and add the key.
4. In **Settings → Environments**, create an environment named `release-push`.
5. Restrict it to **Deployment branches → Selected branches → `main`**.
6. Add one environment secret: `RELEASE_DEPLOY_KEY`, the whole `slovo_release_push` file.
7. Delete both local key files.

No other secret belongs in `release-push`, and the deploy key belongs in no other
environment. That keeps the signing secrets away from the job that can write to
the repository, and the write key away from the job that signs.

### The `main` ruleset

A ruleset on `main` requires a pull request and blocks force pushes and deletion.
Deploy keys are on its bypass list, which is what lets `publish` push the version
bump and the baseline commit. The bypass covers every rule in the ruleset, so
whoever holds the private key can also rewrite `main`. Only `publish` and `record`,
running on `main`, can read it.

Without the key, or with deploy keys off the bypass list, a release packages its
artifacts and then fails at the release push, before any tag or GitHub Release
exists.

## What you observe

- **A releasable push:** a new tag `v<version>` and a GitHub Release appear with
  `Slovo.dmg`, `Slovo.zip`, and `appcast.xml` (the Sparkle auto-update feed)
  attached and generated notes; the `README.md` install link and Release badge
  point at the latest release, so a published release is immediately what users
  download, and installed copies auto-update from the published `appcast.xml`.
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
