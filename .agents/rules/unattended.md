# Working unattended

Rules for any unattended run whose whole job is reading, judging and
reporting, whoever or whatever scheduled it. A session that *implements*
a change follows AGENTS.md and CONTRIBUTING.md instead. Vendor-specific
details below name themselves; running elsewhere, skip the detail, keep
the rule.

## There is no Mac here

Slovo builds only with Xcode 26.4+ on macOS (CONTRIBUTING.md); an
unattended cloud session runs on Linux with no Swift toolchain — no
`swift`, no SwiftLint plugin, no `Scripts/diagnose.sh` or
`Scripts/lint.sh`. So:

- Evidence is reading, history, and GitHub. Nothing can be compiled,
  tested, linted, or run here.
- The compiled-and-tested signal is CI's: `swift.yml` runs
  `swift test --disable-automatic-resolution` on a macOS runner for every
  pull request into `main` and every release build. Read its runs via
  REST instead of guessing at build state.
- A claim that would need a build or a run to confirm is `plausible`,
  never `confirmed`. Say which.
- Never report a check as run that cannot run here; name what substituted
  for it (code read, CI run read, callers traced).

## GitHub: REST, and probe what you need

In an Anthropic cloud session the GraphQL endpoint serves only a pinned
set of PR-review operations; everything else answers 403. That breaks
`gh issue list`, `gh issue view`, `gh issue edit`, `gh repo view`. Prefer
the session's built-in GitHub tools; otherwise `gh api` (REST). Take the
repository from the clone:

    # ERE has no lazy quantifier: two substitutions, or SSH remotes keep ".git"
    R=$(git remote get-url origin | sed -E 's#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#')

    # REST /issues returns pull requests too — the select() is required
    gh api -X GET repos/$R/issues --paginate -f state=open -f labels=<label> \
      --jq '.[] | select(.pull_request | not)
            | {number, title, body, created_at, html_url, labels: [.labels[].name]}'

    gh api -X GET repos/$R/issues --paginate -f state=closed -f labels=<label> \
      --jq '.[] | select(.pull_request | not) | {number, title, body, state_reason}'

    gh api repos/$R/issues/<n>/comments --paginate --jq '.[] | {user: .user.login, body, created_at}'

    gh api -X POST repos/$R/issues            --input issue.json     # {"title":…,"body":…,"labels":[…]}
    gh api -X POST repos/$R/issues/<n>/comments --input comment.json # {"body":…}
    gh api -X POST repos/$R/issues/<n>/labels -f 'labels[]=<label>'
    gh api -X POST repos/$R/labels -f name=<label> -f color=<hex> -f description=<text>

CI state at a commit:

    gh api repos/$R/commits/<sha>/check-runs --jq '.check_runs[] | {name, status, conclusion}'
    gh api -X GET repos/$R/actions/runs -f head_sha=<sha> --jq '.workflow_runs[] | {name, status, conclusion, html_url}'

A label create answering `422` means it already exists — treat as
success. Create every label before its first use.

Never gate a run on `gh auth status`: in a cloud session `GH_TOKEN` holds
a placeholder and the real credential lives outside the container, so the
status check can fail while access is fine. Probe the thing needed:

    gh api repos/$R --jq .full_name

If that fails — or `gh` is missing and the session has no built-in GitHub
tools — stop and say so in the report.

## The clone is shallow

Before anything that reads history (`git log --since=…`, `git blame`,
churn ranking):

    git fetch --unshallow --quiet || true
    test -e .git/shallow && echo "STILL SHALLOW: unshallow failed, history is truncated"

The second line matters: `|| true` also swallows a real fetch failure.
If the marker file remains, say so in the report and treat every
history-based conclusion as drawn from truncated history. Most features
land on `main` as squash merges — the commit message often carries the
whole change's reasoning; read it, not just the diff stat.

## Keep run state in files, not in context

Long runs get their context compacted. Anything that must still be true
at the end — a do-not-report list, candidates, verdicts — goes to disk
the moment it is learned, outside the working tree, in a per-run
directory (never a fixed shared path — sibling sessions can share the
machine):

    RUN=$(mktemp -d /tmp/run.XXXXXX)

Re-read those files immediately before acting on them, and hand a
subagent the path to a long record rather than its text.

## Leave no trace

Throwaway files go under `$RUN`, never the working tree. An analysis run
must not commit, stage, push, or leave any modification behind: it
finishes with `git status --porcelain` empty and says so in its report.

## Reporting a result

Name the command and show what it printed. A check that was not run is
reported as not run — here that is most checks, so the report says what
substituted for each. Never invent a path, a line number or command
output.
