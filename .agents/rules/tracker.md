# Filing issues from an automated run

The tracker discipline for any unattended analysis whose output is a
GitHub issue. What to look for, what disqualifies a candidate, and what
an issue's body contains belong to the run's own instructions; this file
makes every automated filer behave the same.

## Silence is the default

A run that files nothing is a successful run and, in a healthy
repository, the common outcome. Five merely-plausible issues teach the
reader to ignore the label; one actionable issue is the goal. When in
doubt, the doubt goes in the report, not the tracker.

## Before analysing: the do-not-report list

Load what the tracker already holds (the GitHub rules in
`.agents/rules/unattended.md` apply): every issue with the run's own label,
open **and** closed, plus the whole open list — the complete lists, not
the first page of them; a fingerprint missed to truncation becomes a
duplicate issue. Read full bodies — the
HTML fingerprint comment at the end of each automated issue is its
identity. Write the list to `$RUN/do-not-report.md` before any analysis:

- Fingerprint present in **any** state → never report again. Closed means
  a person looked and declined; re-filing is worse than silence.
- An open issue covers the same code or concept under other wording → no
  second issue. Materially new evidence becomes a comment there; anything
  less is left alone.
- An earlier issue of the run's own is now stale (the code it points at
  was fixed or deleted) → one comment saying so, a note in the report;
  the issue stays open — closing is a person's call.
- Skim issues without the run's label too: a user's bug report about the
  same behaviour counts as coverage.

Re-read the file immediately before filing anything.

## Backpressure

Count the open issues carrying the run's own label before analysing, and
cap the run:

| Open issues with the run's label | Maximum filed this run |
| :-- | :-- |
| 0–2 | the run's own cap (3 unless its instructions say lower) |
| 3–4 | 1 |
| 5 or more | 0 — file nothing, and say so |

At cap 0 a light pass still happens so the report is honest. Only the
run's one named exception (if it has one) may override the cap.

## Independent triage

The analyst does not choose what gets filed — its judgement is
contaminated by the effort spent. Every candidate surviving the analyst's
own verification is judged by subagents that share none of its context:

- **One verification subagent per candidate, in parallel.** The brief is
  neutral and self-contained — the claim in a sentence or two, paths and
  line ranges, the proposed action; none of the analyst's evidence,
  confidence, or hints, and no sight of other briefs. The verifier
  re-derives the facts from the repository, actively tries to **refute**
  the claim, checks AGENTS.md, `docs/` and the rule files for a recorded
  justification of the current shape, and rejects when uncertain. It
  returns the run's verdict schema — always including
  `verdict: real | not-real` and a 1–5 confidence.
- **A threshold, applied silently.** The run's instructions define it
  (default floor: `verdict = real` and `confidence >= 4`). What falls
  below is dropped, never filed "for visibility".
- **One ranking subagent, clean context.** It receives one line per
  surviving claim — title, kind, scores — and this, verbatim:

  > An empty shortlist is a valid and expected answer. Include an item
  > only if you would put it on a senior engineer's plate and defend that
  > choice in review. You are not filling a quota; the cap is a ceiling,
  > not a target.

  It returns at most the cap, ranked, with one line of justification each
  and what it dropped and why.

**The shortlist is final.** A verifier's `not-real` drops the candidate
even when the analyst disagrees — the disagreement goes in the report. An
item may be removed (a late-spotted duplicate fingerprint), never added
back. An empty shortlist is a normal outcome.

## Filing

Labels first, created per `.agents/rules/unattended.md`. One issue per
finding, never bundled, never more than the cap, each ending with an
HTML-comment fingerprint stable enough for the next run to recognise.
Consult the do-not-report file once more immediately before each create.

## The report

Every run ends with a report in this fixed shape:

1. **Coverage** — what was swept and what was not reached.
2. **Candidates** — found / cut by the analyst / handed to triage.
3. **Triage** — verifier rejections with grounds, one line each; what the
   ranker dropped and why.
4. **Filed** — the issues with URLs, or the single line `Filed nothing.`
5. **Strongest rejected** — the two or three best unfiled candidates,
   with reasons. The most useful section of a quiet week.
6. **Blockers** — what `unattended.md` calls a blocker (the absent Apple
   toolchain is not one), and the `git status --porcelain` result.

Filing nothing is stated in one line, without apology.

## Hard constraints

- Never modify, commit, or push code. Never open a pull request. Never
  edit or close issues the run did not create.
- Never exceed the cap (outside the run's one named exception), re-file
  an existing fingerprint, or file a candidate the verifiers rejected or
  the ranker dropped.
- Never file an issue to demonstrate that the run happened.
- If the tree is visibly broken — CI red on `main` at the commit under
  analysis, a manifest that cannot parse — say so in the report and stop,
  without filing an issue about it. The team already knows.
