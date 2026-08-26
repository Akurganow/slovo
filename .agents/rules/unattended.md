# Working unattended

Rules for any unattended run whose whole job is reading, judging and
reporting — whoever scheduled it, wherever it runs. A session that
*implements* a change follows AGENTS.md and CONTRIBUTING.md instead.

## Claim only what you ran

Slovo builds only with Xcode 26.4+ on macOS (CONTRIBUTING.md). Before
claiming any build, test, or lint result, prove that toolchain exists
where you are running; without it, evidence is reading the code, reading
history, and reading CI results, and a conclusion that would need a
build or a run to confirm is `plausible`, never `confirmed` — say which.
A check that was not run is reported as not run, together with what
substituted for it.

## GitHub

- Use the GitHub REST API through whichever client the session has.
  Confirm access with a real request — fetch the repository — before
  relying on it, and trust that over any auth-status helper. If no
  available client reaches the API, stop and say so in the report.
- An issues listing includes pull requests; filter them out.
- Creating a label that already exists is success; any other creation
  failure is real. Create every label before its first use.
- Read CI state for a commit from the API instead of guessing at build
  state.

## History

Make sure the clone carries full history before drawing any conclusion
from history; if full history cannot be fetched, say so in the report
and treat every history-based conclusion as drawn from a truncated one.
Most features land on `main` as squash merges — the commit message often
carries the whole change's reasoning; read it, not just the diff.

## Run state

Anything that must still be true at the end of a long run — lists,
candidates, verdicts — goes to a file the moment it is learned, in a
private per-run directory outside the working tree (the `$RUN` other
rules refer to), and is re-read immediately before it is used. Hand a
subagent the path to a long record, never its text.

## Leave no trace

Throwaway files go to the per-run directory, never the working tree. An
analysis run must not commit, stage, push, or leave any modification
behind: it finishes with `git status --porcelain` empty and says so in
its report.

## Reporting a result

Name the command and show what it printed. Never invent a path, a line
number, or command output.
