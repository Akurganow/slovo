# Threat model: what an outside party could reach

Facts of this repository that a security review is argued against. Its
readers are whoever reviews the repository for what an outside party could
exploit. What `SECURITY.md` and `docs/` say about a protection is a claim.
Measure it against the pipeline definitions and the protection settings as
read.

## The model

- The repository and its whole history are public. A secret in any commit is
  a published secret, so judge all of history, not the tree alone.
- The fleet's roles act under a trusted identity, read third-party text and
  write to the tracker (`.agents/rules/unattended.md`, "Instructions and
  evidence"). Where third-party text crosses from data into an instruction
  is a security question.
- A person merges. The protection of `main` and of each deployment
  environment is read as the code host reports it.
- A releasable merge signs, notarizes and publishes an update that installed
  copies take on their own (`docs/release-ci.md`).
- Every push to a pull request starts CI on a macOS runner, and the
  `dev-build` label starts a signing job.

## Surfaces

1. **Secrets**, in the tree and in all history: the signing certificate and
   its password, the notarization key and its identifiers, the update feed's
   EdDSA private key (`docs/release-ci.md`, "One-time owner setup"), and the
   cleanup provider's API key (`docs/privacy.md`, "Keychain"). Also every step
   that could echo a secret into a public log.
2. **Workflows**: every workflow under `.github/workflows/` and every script
   it calls. They sign, notarize, publish or push. The closest read goes to
   `.github/workflows/release.yml` and `.github/workflows/dev-build.yml`.
   The inputs an outsider can influence are a title, a body, a branch name, a
   label name and comment text.
3. **The agentic surface**: the roles acting as a trusted identity, the
   labels that start work, every path by which a role pushes or opens a pull
   request, and the trust rules (`.agents/rules/unattended.md`, "Instructions
   and evidence"; `.agents/skills/pipeline-law/SKILL.md`, "What a fired stage
   trusts" and "Pushes"). The issue templates under `.github/ISSUE_TEMPLATE/`
   belong here: a template that applied `police-report` would let a
   stranger's issue into the machine population (`.agents/rules/filing.md`,
   "The machine population").
4. **The update channel**: Sparkle's `SUFeedURL` and `SUPublicEDKey` in
   `Resources/Info.plist`, and the appcast the `package` job of
   `.github/workflows/release.yml` signs.
5. **Rendered output**: `CHANGELOG.md` and the GitHub release notes. The
   `publish` job of `.github/workflows/release.yml` renders both from merged
   pull-request titles, which anyone who opens a pull request writes.
   - `CHANGELOG.md`: `git-cliff --prepend` renders each merged commit header,
     which GitHub pre-fills from the pull-request title (`AGENTS.md`, "Before
     you open a pull request"). The body template in `cliff.toml` prints
     `commit.message` through `upper_first` alone, and `cliff.toml` declares
     no preprocessor and no postprocessor. Its commit parsers keep only
     `feat`, `fix`, `perf` and breaking headers: a filter on the type that
     leaves the text as written.
   - The release notes: `gh release create --generate-notes` has GitHub
     generate them, and they list the merged pull requests. Each entry
     carries the pull request's title as written. No `.github/release.yml`
     configures them.

   No sanitizer of the project's stands between a title and either output.

This file describes the tree and the pipelines. Where they disagree with it,
they win and this file is stale.
