# Boundaries: closed paths and decisions that need a person

What no hand edit touches, what never enters the tree or a published page,
and which decisions only a person makes.

## Closed paths

A path here is never edited by hand, by a person or a role. A wrong value in
one is judged at whatever writes it. A rule that cannot be a path, such as
one key inside an ordinary file, lives only in this table.

| Path | Why it is closed | Where the decision is recorded |
| :-- | :-- | :-- |
| `CHANGELOG.md` | The release pipeline writes each section from the merged commit headers | `docs/release-ci.md`, "Changelog" |
| The keys `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` | The release pipeline stamps the version. Nobody moves a version by hand | `docs/release-ci.md`, "Versioning"; `CONTRIBUTING.md`, "Packaging" |
| Tags `v*` | Only the release pipeline creates them | `docs/release-ci.md`, "Why one run does everything (no PAT, no double-fire)" |
| `Benchmarks/cleanup/baseline.json` | The benchmark command writes it, and the cleanup benchmark workflow records it on `main`. Never edited by hand | `docs/release-ci.md`, "Cleanup benchmark" |
| `data/seed*.sql`, `data/*.db*` | Personal vocabulary and the local database. Never committed | `.gitignore`; `AGENTS.md`, "Before you open a pull request" |
| `secrets/`, `.env*`, `*.key`, `*.pem`, `*.p12`, `*.p8`, `*.token`, `credentials*.json`, `id_rsa*` | Key material and credentials. Never committed | `.gitignore`; `AGENTS.md`, "Before you open a pull request" |

## What never appears in the tree or on a published page

A published page is an issue, a comment, a pull request, a commit message or
a release.

- Secrets, local databases, seed files and signing material (`AGENTS.md`,
  "Before you open a pull request").
- Raw audio, transcripts, personal vocabulary and private work terms
  (`SECURITY.md`, "Sensitive Data").
- A session link (`AGENTS.md`, "Standing owner directives").
- A fact of the machine a caller runs on: its paths, tool versions,
  accounts, identities or schedule. The owner decided this: such facts
  belong to the caller (`.agents/rules/context.md`, "The context standard").

## Decisions that need a person

The writes a person always makes are listed in `AGENTS.md`, "This
repository's own machinery".

**No role ever pushes to `main`.** Not a commit, a merge, a tag, a branch
update or a force-push, by any route, for any reason.

- A change a role makes reaches `main` only through a person's merge of a
  pull request.
- A role whose work needs a commit on `main` stops, writes nothing more, and
  says so in its report.

The release pipeline is not a role. Its commits on `main` are two: the version
bump and the baseline record (`docs/release-ci.md`).

This file describes `.gitignore`, the release pipeline of
`.github/workflows/release.yml` and the cleanup benchmark of
`.github/workflows/cleanup-benchmark.yml`. Where they disagree with it, they win
and this file is stale.
