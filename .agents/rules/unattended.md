# Working unattended

Rules for any unattended run whose whole job is reading, judging and
reporting — whoever scheduled it, wherever it runs. A session that
*implements* a change follows AGENTS.md and CONTRIBUTING.md instead.

## Claim only what you ran

Slovo builds only with Xcode 26.4+ on macOS (CONTRIBUTING.md), and an
unattended run gets a Linux container: nothing is ever built, tested,
linted or run here. That is the standing condition of every run, not a
fault of this one. Before claiming any build, test, or lint result,
prove that toolchain exists where you are running; without it, evidence
is reading the code, reading history, and reading CI results, and a
conclusion that would need a build or a run to confirm is `plausible`,
never `confirmed` — say which. A check that was not run is reported as
not run, together with what substituted for it.

What substitutes is a real macOS run that has already happened.
`swift.yml` runs `swift test --disable-automatic-resolution` on a
`macos-26` runner, and SwiftLint rides inside that build as a SwiftPM
build-tool plugin, so a lint violation there is a build failure. The run
covering a given commit is found by where the commit sits:

- on `main` — the **Release** run for that sha, which calls `swift.yml`
  as its `test` job and names the gate at that exact sha in
  `referenced_workflows`;
- a pull request head — the **Swift** run for that sha.

Cite that run, by number and conclusion, as the baseline. It does not
cover `swiftlint analyze`, `plutil -lint`, the shell-syntax stage or the
explicit-target-import check: those live in `Scripts/lint.sh` and run
only on a Mac, so a claim resting on one of them stays `plausible`.

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
- The session's token can also write to Actions — it dispatches and
  re-runs workflows as the owner. An analysis run never does: the gate
  has already run on the commit under analysis, macOS minutes are scarce
  (`swift.yml` cancels superseded runs to save them), and a run reading
  third-party issue text must not be able to start jobs on that runner.
  Read runs; never start one.

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
analysis run must not commit, stage, push, or add any modification of
its own: record `git status --porcelain` before starting, require the
final output to match it exactly, and say so in the report. Pre-existing
changes are preserved, never cleaned up.

## Reporting a result

Name the command and show what it printed. Never invent a path, a line
number, or command output.

A blocker is what stopped this run and a person could clear: denied
network, a GitHub error, a missing rule file, history that would not
fetch. The absent Apple toolchain is not one — it is the standing
condition above, so it belongs where the run states what its evidence
rests on, never in the list whose only job is to make the owner go and
look.
