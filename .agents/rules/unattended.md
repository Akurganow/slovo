# Working unattended

How an **analysis run** works in this repository when nobody is present to
answer: any unattended run whose whole job is reading, judging and
reporting, whoever or whatever scheduled it. An autonomous session that
*implements* a change is a different animal: it follows AGENTS.md and
CONTRIBUTING.md, and this file does not govern it.

The other documents say what is true of Slovo; this one says what is true
of running in it alone. Where a detail below is specific to one vendor's
cloud environment, it says so — an agent running elsewhere skips that
detail, not the rule it serves.

## There is no Mac here

Slovo builds only with Xcode 26.4+ on macOS (CONTRIBUTING.md); an
unattended cloud session runs on Linux. `swift`, the SwiftLint build
plugin, `Scripts/diagnose.sh` and `Scripts/lint.sh` do not exist in this
container and cannot be made to. Accept that instead of working around it:

- Your evidence is **reading, history, and GitHub** — the sources, the
  documents, `git log`/`blame`, CI results and the tracker. You cannot
  compile a candidate fix, run a scratch test, or lint anything.
- The compiled-and-tested signal exists and is CI's: `swift.yml` runs
  `swift test --disable-automatic-resolution` on a macOS runner for every
  pull request into `main` and for every release build. Read its runs
  through the REST API rather than guessing at build state.
- A claim that would need a build or a run to confirm is `plausible`,
  never `confirmed`. Say which it is; the reader plans differently for
  each.
- Never report a check as run that cannot run here. "Tests pass" from a
  container that has no toolchain is an invented result — name what you
  actually did instead (read the code, read the CI run, traced the
  callers).

## GitHub: REST, and probe what you need

In an Anthropic cloud session, GitHub traffic goes through a proxy that
serves **only a pinned set of pull-request GraphQL operations**. Everything
else on the GraphQL endpoint fails:

    403 This GraphQL query is not enabled for this session — only the pinned
    set of PR-review operations is served. Use REST via
    `gh api repos/{owner}/{repo}/...` instead.

`gh issue list`, `gh issue view`, `gh issue edit` and `gh repo view` are
GraphQL-backed — do not use them there. Prefer the session's built-in GitHub
tools when it has them; otherwise `gh api` (REST). Take the repository from
the clone, not from `gh repo view`:

    # two substitutions on purpose: ERE has no lazy quantifier, so a single
    # pattern with an optional `(\.git)?` tail lets the greedy class swallow
    # the suffix and returns "owner/repo.git" for SSH-style remotes.
    R=$(git remote get-url origin | sed -E 's#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#')

    # open issues carrying a label. REST /issues returns pull requests too —
    # the select() is required, `gh issue list` used to do it for you.
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

CI state at a commit, through the same door:

    gh api repos/$R/commits/<sha>/check-runs --jq '.check_runs[] | {name, status, conclusion}'
    gh api -X GET repos/$R/actions/runs -f head_sha=<sha> --jq '.workflow_runs[] | {name, status, conclusion, html_url}'

Creating a label that already exists answers `422`; treat that as success,
and create every label before its first use — a create that names a missing
label fails after the analysis it was meant to publish.

**Never gate a run on `gh auth status`.** In a cloud session `GH_TOKEN`
reads the literal placeholder `proxy-injected` and the real credential lives
outside the container, so the status check can fail while access is fine —
and an unattended run that stops there has spent itself on nothing. Probe
the thing actually needed:

    gh api repos/$R --jq .full_name

If that fails, stop and say so in the final report. If `gh` is missing and
the session has no built-in GitHub tools either, stop and say that.

## The clone is shallow

A cloud session's clone is truncated (`.git/shallow` exists). Before
anything that reads history — `git log --since=…`, `git blame`, churn
ranking, any archaeology — run:

    git fetch --unshallow --quiet || true
    test -e .git/shallow && echo "STILL SHALLOW: unshallow failed, history is truncated"

The `|| true` keeps an already-full clone from failing the run, but it also
swallows a real fetch failure — hence the second line. If the marker file is
still there, the fetch did not happen: say so in the report, and treat every
history-based conclusion as drawn from truncated history, because it was.

Most feature history lands on `main` as squash merges of pull requests, so
one commit often carries a whole change with its reasoning in the body —
read the message, not just the diff stat.

## Keep run state in files, not in context

Long unattended runs get their context compacted, and a compaction can drop
exactly the thing that mattered at the last step. Anything that must still
be true at the end — a do-not-report list, collected candidates, verdicts —
goes to disk the moment it is learned, outside the working tree.

The state directory is **per-run, never a fixed shared path**: the machine
can be shared by sibling sessions, and two runs sharing `/tmp/run` would
overwrite each other's state — the do-not-report list first, which is the
one file whose integrity the whole protocol rests on. Make one at the start
and use it everywhere:

    RUN=$(mktemp -d /tmp/run.XXXXXX)

Re-read those files immediately before acting on them, and hand a subagent
the path to a long record rather than its text.

## Leave no trace

Writing throwaway files is allowed — under the run's own `$RUN` directory,
never in the working tree. An analysis run must not commit, stage, push, or
leave any modification behind: it finishes with `git status --porcelain`
empty and says so in its report. A run whose whole job is analysis has no
business changing what it analysed.

## Reporting a result

Name the command and show what it printed. A check that was not run is
reported as not run — not as passing, and not omitted; here that is most
checks, because the toolchain is a Mac's (see above), so the report says
what substituted for each: which CI run was read, which code was traced.
Unattended it matters twice over, because nobody was watching, so the
report is the only record that the run did what it claims. Never invent a
path, a line number or command output.
