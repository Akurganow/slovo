# Filing issues from an automated run

The protocol any unattended analysis follows when its output is a GitHub
issue. The analysis itself — what to look for, what disqualifies a
candidate, what an issue's body must contain — belongs to whoever runs the
analysis; this file owns the tracker discipline around it, so that every
automated filer behaves the same way and the tracker stays worth reading.

## Silence is the default

Filing an issue is not the goal of a run and is not expected of it. A run
that files nothing is a successful run and, in a healthy repository, the
common outcome. One issue a maintainer acts on is worth more than five that
are merely plausible; the five teach the reader to ignore the label, and
the one real finding gets ignored with them. When in doubt, stay silent —
the run's report (below) is where doubt goes.

## Before analysing: the do-not-report list

First load what the tracker already holds, with the REST calls from
`.agents/rules/unattended.md`: every issue carrying the run's own label,
open **and** closed, and the whole open list. Read full bodies, not titles —
each automated issue ends with a fingerprint comment, and the fingerprint is
the identity. Build a do-not-report list and write it to a file
(`$RUN/do-not-report.md`, in the per-run state directory
`.agents/rules/unattended.md` prescribes) before any analysis:

- Fingerprint present in **any** state → never report it again. A closed
  issue means a person looked and declined; re-filing is worse than silence.
- An open issue covers the same code or concept under different wording →
  no second issue. Materially new evidence becomes a comment on the
  existing issue; anything less is left alone.
- An earlier issue of the run's own is now stale (the code it points at was
  fixed or deleted) → one comment saying so, a note in the report, and the
  issue stays open — closing is a person's call.
- Issues without the run's label are skimmed too: a person may already have
  filed the same thing. Slovo's users file bugs through the issue
  templates, and a user report about the same behaviour counts as coverage.

Re-read the file immediately before filing anything — the list must survive
to the moment it is needed, not just the moment it was built.

## Backpressure

An untouched backlog means the team is not consuming what the runs produce,
and adding to it is pure noise. Count the open issues carrying the run's own
label before analysing anything, and cap the run:

| Open issues with the run's label | Maximum filed this run |
| :-- | :-- |
| 0–2 | the run's own cap (3 unless its instructions say lower) |
| 3–4 | 1 |
| 5 or more | 0 — file nothing, and say so |

When the cap is 0, a light pass still happens so the report is honest, but
nothing is filed. A run's instructions may name one narrow exception that
overrides the cap (a reproduced critical defect, a security advisory);
absent that, nothing does.

## Independent triage

The analyst does not choose what gets filed: its judgement is contaminated
by the effort already spent on each candidate. Every candidate that survives
the analyst's own verification is judged by subagents that share none of its
context.

**One verification subagent per candidate, in parallel.** The brief is
self-contained and neutral: the claim in one or two sentences, the paths and
line ranges, the proposed action. It carries none of the analyst's evidence,
reasoning, confidence, effort spent, candidate count, or any hint of a
preferred answer, and subagents never see each other's briefs. Each subagent
re-derives the facts from the repository itself, actively tries to
**refute** the claim, checks AGENTS.md, `docs/` and the rule files for a
recorded justification of the current shape, and defaults to rejecting when
uncertain. It returns the structured verdict the run's instructions define —
always including `verdict: real | not-real` and a 1–5 confidence.

**A threshold, applied silently.** The run's instructions define it (the
default floor: `verdict = real` and `confidence >= 4`). What falls below is
dropped without being filed "for visibility".

**One ranking subagent, clean context.** It receives the surviving claims as
one line each — title, kind, scores, none of the analyst's reasoning — and
this, verbatim:

> An empty shortlist is a valid and expected answer. Include an item only if
> you would put it on a senior engineer's plate and defend that choice in
> review. You are not filling a quota; the cap is a ceiling, not a target.

It returns at most the backpressure cap, ranked, with one line of
justification each and an explicit list of what it dropped and why.

**The shortlist is final.** A candidate its verifier marked `not-real` is
dropped even when the analyst disagrees — the disagreement goes in the
report, never in an issue. The run files exactly what the ranker
shortlisted, in its order; an item may be removed (a late-spotted duplicate
fingerprint), never added back. An empty shortlist means filing nothing, and
that is a normal outcome, not a threshold to relax.

## Filing

Labels first, created the way `.agents/rules/unattended.md` prescribes —
that file owns the mechanics, including what a duplicate answers. One issue
per finding, never bundled, never more than the cap. Each issue ends with an
HTML-comment fingerprint that names the finding stably enough for the next
run to recognise it. Immediately before each create, the do-not-report file
is consulted once more.

## The report

Every run ends with a report in a fixed shape, because reports that share a
shape can be compared across weeks:

1. **Coverage** — what was swept, and what was not reached, so the next run
   can start there.
2. **Candidates** — found / cut by the analyst / handed to triage.
3. **Triage** — what the verifiers rejected and on what grounds, one line
   each; what the ranker dropped and why.
4. **Filed** — the issues with URLs, or the single line `Filed nothing.`
5. **Strongest rejected** — the two or three best candidates that were not
   filed, with the reason. This is the most useful section of a quiet week.
6. **Blockers** — missing tools, denied network, GitHub errors, and the
   `git status --porcelain` result.

Filing nothing is stated in one line, without apology or hedging. The report
is the deliverable of a quiet week; it is not a failed run.

## Hard constraints

- Never modify, commit, or push code. Never open a pull request. Never edit
  or close issues the run did not create.
- Never exceed the backpressure cap (outside the run's one named exception,
  if it has one), never re-file an existing fingerprint, never file a
  candidate the verifiers rejected or the ranker dropped.
- Never file an issue to demonstrate that the run happened.
- If the tree is visibly broken — CI red on `main` at the commit under
  analysis, a manifest that cannot parse — the report says so and the run
  stops, without filing an issue about it. The team already knows.
