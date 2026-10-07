# Police: what every police role shares

A police role sweeps one subject of the repository, proves each candidate,
passes the survivors through independent triage, and files at most a few
issues. It changes no file. These rules extend `.agents/rules/unattended.md`
and `.agents/rules/filing.md`. A role file names this file and never
restates it.

## Shared rules

- **Prefer filing nothing over filing a guess.** A quiet run is the expected
  outcome, and its report is the deliverable.
- **Route first.** Route every candidate by the ownership table in
  `.agents/rules/filing.md`, "Ownership routing", before spending a minute on
  it.
- **Measure, then write the alternative.** A candidate is not a finding
  until it carries three things:
  - the measurement its kind prescribes;
  - the alternative written out in full, as real code or as the corrected
    text;
  - for history-based kinds, the two commits that bracket it.

  "No measurement, no finding: that is taste." If writing the alternative
  reveals why the current shape exists, that is the run working. Record it
  and drop the candidate.
- **The issue is the only surviving copy of the alternative.** `$RUN` does
  not outlive the fire. The issue body carries the alternative in full and
  never points at a scratch path.
- **Attack your own claim once** before triage. Look for a caller-side
  guarantee, a type invariant, an assertion, upstream validation, a pinning
  test, a recorded reason. If one holds, drop the candidate.
- **Never a finding:** style, linter-owned issues, performance-only
  concerns, theory with no reachable path, and taste. A role's "Not
  findings" adds only what is its own.
- **Recorded reasons protect a shape.** A comment, rule file, doc entry,
  owner directive or test note that explains the current shape closes the
  candidate. Disagreeing with a recorded decision is a conversation for the
  owner, in the report, never an issue. A claim of fact inside a recorded
  reason is still judged against the code.
- **Value scales have written anchors.** Each role's `value: 1-5` describes
  1, 3 and 5 in words, so the floor is not the verifier's taste.
- **A census that reports zero proves nothing** until it has reported
  non-zero on a planted positive. A search that exits with an error can read
  like a clean tree.
- **No scope beyond the role's stated intent.** A new sweep is a change to
  the role file, never a run's initiative.
- **Police roles take no payload.** A payload on a police fire is reported
  in one line and ignored. The role sweeps its whole subject.
- **One cost line for every body.** Each body's "Cost and risk" section, or
  its Severity section where the role grades severity, reads
  `Effort: S|M|L — Risk: low|medium|high — Confidence: confirmed | demonstrated | plausible`.
  A Severity section puts the severity and a dash before it. The confidence
  words are defined in `.agents/rules/unattended.md`, "Claim only what you
  ran".
- **The churn window is the last 90 days.** A role that ranks files by churn
  counts commits over it, on full history only. On a shallow clone the
  ranking is reported as truncated, never presented as a ranking.
- **Re-measure every number at the analysed commit.** A number carried over
  from an older commit goes stale when the tree moves.
- **A remedy is a proposal.** It names the verification that must run, never
  claims this run verified it.
- **Strongest rejected** lists the candidates a recorded reason killed. That
  list shows the owner which decisions read as arbitrary to an outside eye.
- **Fence proposals.** A tell that recurs across files and could be matched
  by a pattern is a proposal for a check. It goes in the report, with the
  pattern, shown firing on a real or planted instance. A proposed check that
  could never fire is ceremony and is not proposed. Never add a check on the
  spot.

## The fence

Everything the CI gate rejects cannot exist on a green `main`. Reporting it
means a misread, so aim strictly above it. The fence is
`.agents/rules/verification.md`, "What the gate rejects". It has nothing to
do with fenced data, the boundary around third-party text
(`.agents/rules/unattended.md`, "Instructions and evidence").

**The verifier brief carries the fence verbatim**, because the verifier never
sees the role file. A verifier without it judges fenced items as findings.

## Name the rulebook

Each role file names the document the court tries its findings by, or "none"
where the court's own inputs suffice. A role that names one writes it into
every issue body, on the line after the analysed commit:

```
Judged by: <document>
```

The line tells a reader which document applies. The court checks it against
the filer's role file. Where they disagree, the role file wins.
