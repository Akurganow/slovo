# Working unattended

Rules for any unattended run whose whole job is reading, judging and
reporting — whoever or whatever scheduled it, on whatever platform it
runs. A session that *implements* a change follows AGENTS.md and
CONTRIBUTING.md instead.

## There is no Mac here

Slovo builds only with Xcode 26.4+ on macOS (CONTRIBUTING.md), and an
unattended runner is almost never that Mac. Without the toolchain there
is no `swift`, no SwiftLint plugin, no `Scripts/diagnose.sh` or
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

No GitHub client is guaranteed here, and a proxied environment may serve
only a fraction of the API — GraphQL is the part most often missing. So
these rules are stated at the protocol level, in plain REST, which every
environment serves: satisfy each with whichever client the session has —
built-in GitHub tools, a CLI, plain HTTPS. What matters is the request,
not the tool.

- REST, never GraphQL: helpers riding GraphQL can fail wholesale behind
  a proxy; the REST requests below work everywhere.
- Take owner/repo from the clone's `origin` remote, never from a
  "current repository" helper.
- Issues: `GET /repos/{owner}/{repo}/issues` with `state` and `labels`
  filters, paginated. The endpoint returns pull requests too — drop
  every item carrying a `pull_request` key. The whole open list (the
  do-not-report pass in tracker.md needs it) is the same call without
  the `labels` filter.
- Comments: `GET`/`POST /repos/{owner}/{repo}/issues/{n}/comments`.
- Filing: `POST .../issues` (title, body, labels); labels via
  `POST .../labels` (name, color, description) and
  `POST .../issues/{n}/labels`.
- A label create can answer `422` for more than one reason: treat it as
  success only when the body's `errors[].code` says `already_exists`;
  any other `422` is a real failure. Create every label before its
  first use.
- CI at a commit: `GET /repos/{owner}/{repo}/commits/{sha}/check-runs`
  and `GET /repos/{owner}/{repo}/actions/runs?head_sha={sha}`.
- Never gate the run on an auth-status check: in a proxied environment
  the real credential lives outside the process (a placeholder token in
  the environment variables is normal), so such a check can fail while
  access is fine. Probe the
  thing actually needed — `GET /repos/{owner}/{repo}` — and only if that
  fails with every client the session has, stop and say so in the
  report.

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
