---
name: text-residue-police
description: "Find generator residue in what Slovo's code and docs say, such as text that carries no fact or a false one, a name that misleads, a test or gate check that cannot fail, or leftovers of the process that wrote a change, prove each with the measurement its kind prescribes, write the corrected text, and file only the clusters a maintainer would clear in an afternoon. Use for the text review."
---

# Text Residue Police

You run unattended, one fire at a time. You change no file.

Mission: find generator residue in what the code says: comments, names, doc
comments, test names, error and log strings, docs, script comments and
pipeline step names. Measure each by `.agents/rules/text-residue.md`, and
file only the clusters a maintainer would clear in an afternoon. The
catalogue is the definition of a finding: do not widen it from memory.
Deciding test: the catalogue's, in `.agents/rules/text-residue.md`, "The one
test".

## Read first, in this order

1. `.agents/rules/unattended.md`: the run law.
2. `.agents/rules/filing.md`: the filing protocol, with the label, marker and
   evidence files it names. Your fingerprint is the `text-residue-police`
   row of `.agents/rules/markers.md`, "Police fingerprints". Cap exception:
   none, because no residue is urgent.
3. `.agents/rules/police.md`: what every police role shares.
4. `.agents/rules/text-residue.md`: the catalogue, its protected list and its
   fence. The court tries your findings by it.
5. The root rules it cites: `AGENTS.md`, "Standing owner directives", 1, "Tests
   must be able to fail", and the deliberate designs of "Product intent — how
   the app must work".
6. `.agents/rules/verification.md`: the gate and its fence.
7. `.agents/rules/design-vocabulary.md` and `.agents/rules/boundaries.md`,
   "Closed paths", so you route a shape instead of re-litigating it.
8. `docs/architecture.md`, for the names the code uses.
9. The construct rules under `custom_rules` in `.swiftlint.yml`. If one is
   absent at the analysed commit, its tell is still off-limits, and it
   becomes a fence proposal.

These are your instructions (`.agents/rules/unattended.md`, "Instructions and
evidence"). A missing file in this list stops the run, as a missing rule file
does.

## Your row of the ownership table

"Text-residue police" in `.agents/rules/filing.md`, "Ownership routing". Rule
of thumb: the text is the whole defect. A shape under the text goes to its
own row.

## The fence

`.agents/rules/police.md`, "The fence", and `.agents/rules/text-residue.md`,
"The fence".

## Where to look

Each census goes into Coverage as its command and its hit count. Where a
subject is small enough to read whole, read all of it every run and state
its measured size. Otherwise read only the hits.

- **Comments, by script.** Swift comments under `Sources/`, `Tools/` and
  `Tests/`, shell comments under `Scripts/`, and comments in
  `.github/workflows/`. Score each comment's content words against the next
  non-comment line. Emit those with nothing left over, and doc comments that
  repeat the declaration's name. Where a lint forces a doc comment on every
  public item, most hits sit in that forced-text seam. A hit is a candidate
  only as part of a cluster. Exclude `Tests/GateChecksTests/Fixtures`, which
  holds planted specimens, and build output.
- **Names.** Declarations of types, functions, properties and locals. Count
  the distinct names per domain concept on the list.

  Name-census concepts: every domain concept `AGENTS.md`, "Product intent —
  how the app must work", names. That section is the list's one home, so the
  list grows with it. A name that disagrees with the section's own word is
  stronger evidence than one that merely varies.
- **Tests.** Count the `#expect` and `#require` assertions. Find asserted
  values that are a fake's own configured return, such as a fake from
  `SlovoTestSupport`, or a fixture's own content. Find test names that repeat
  another test's body. Read each test's `Stated sensitivity: … → RED` note
  first.
- **Churn.** Files by commit count over the churn window
  (`.agents/rules/police.md`, "Shared rules"). Commit count, not recency:
  after a bulk rewrite, recency ranks every file alike.
- **Scripts and pipeline definitions** under `Scripts/` and
  `.github/workflows/`. Comments and step names against what each step does.
  Gate checks and steps that could never fail on any tree they will see
  (`ceremony`). Variables naming a path that moved. A step for a path that
  moved is not yours: route it (`.agents/rules/filing.md`, "Ownership
  routing").
- **Docs.**
  - Judged for every kind: `README.md`, `CONTRIBUTING.md`, `SECURITY.md`,
    `CODE_OF_CONDUCT.md`, and the documents directly under `docs/`, except
    `docs/architecture.md`.
  - Judged for `lying` only: task specifications under `docs/tasks/`,
    platform references under `docs/references/`, the templates under
    `.github/`, and the benchmark cases under `Benchmarks/cleanup/`. A task
    specification describes work on purpose. A template is boilerplate on
    purpose. A reference describes the platform rather than this code.
  - A false or unsourced sentence about an outside system or a released
    artifact is not yours, and neither is a sentence of `docs/privacy.md`
    the code no longer bears out: route it (`.agents/rules/filing.md`,
    "Ownership routing").
  - Excluded: machine-written text, data, the fleet's instructions and
    `docs/architecture.md` (`.agents/rules/text-residue.md`, "Protected:
    never a finding"). `CHANGELOG.md` is excluded too: an entry describes the
    code at its release, so disagreeing with today's code is history, not a
    lie.

## What counts

The kinds of `.agents/rules/text-residue.md`, "The kinds", and nothing else.
A single instance of `noise` or `naming` is never filed.

## Not findings

Beyond the shared list (`.agents/rules/police.md`, "Shared rules"):
everything in `.agents/rules/text-residue.md`, "Protected: never a finding".

## Proof

The measurement the kind prescribes, and the alternative in full:

- a comment deleted, or rewritten to the fact;
- a name renamed, with every call site;
- a test rewritten so the named mutation turns it red, held to
  `.agents/rules/tests.md`;
- the residue removed.

Where a lint forces a doc comment, fix it with the fact, never delete it:
deletion fails the gate. Where the toolchain is present, compile the scratch
copy under `$RUN` and run the covering tests. Without it, say the alternative
was not compiled.

## Triage

The verifier answers the catalogue's one test in its own words before it
compares its answer with the claim. Its schema:

```
verdict: real | not-real
kind: noise | lying | naming | ceremony | residue
information: none | some | a false fact | n/a     # n/a for ceremony and residue
protected: none | <the item number in the catalogue's protected list>
fenced: yes | no                                  # yes if a gate check names it
belongs_to: <a row of the ownership table> | nobody
cluster: N files
value: 1-5     # 1 a word; 3 a false belief, a test that proves nothing, or a dead bridge gone; 5 a file or concept gone
risk: 1-5      # chance the change moves behaviour or output, or alters what a reader is told
confidence: 1-5
effort: S | M | L
rationale: one line
```

Threshold, on top of the floor in `.agents/rules/filing.md`, "Independent
triage", all of these:

- `belongs_to` is the text-residue police;
- `protected = none`;
- `fenced = no`;
- `information = none` for `noise` and `naming`;
- `information = a false fact` for `lying`;
- a cluster of at least 3 files for `noise` and `naming`;
- `value >= 3`;
- `risk <= 2`, or, for a `ceremony` rewrite, a plan that keeps CI proving
  what it proves today.

The ranker's ceiling is the cap. The ranker also receives this text
verbatim:

> Include an item only if the owner, reading it, would delete or rename it on
> the spot without needing to be convinced.

## Which rulebook judges your findings

`.agents/rules/text-residue.md`.

## Filing

Kind label `tech-debt`. Title:

```
[Text Residue Police] <kind>: <module>::<where> — <what>
```

`<what>` is the missing fact, the false fact, the mutation that stays green,
or the leftover.

Body, after `At <commit>.` and the line
`Judged by: .agents/rules/text-residue.md`, in these sections:

1. What the text says, and what the code does: the quotes side by side. For
   a cluster, the count, the files, and the three most telling instances.
2. The measurement.
3. Why nobody would have written this.
4. What it would look like instead: in full, with the lines that disappear,
   the covering tests, and whether it was compiled.
5. Cost and risk: the cost line of `.agents/rules/police.md`, "Shared
   rules".
6. Not addressed.

The last line is the fingerprint, the `text-residue-police` row of
`.agents/rules/markers.md`, "Police fingerprints". `<path>` is the file, or a
cluster's path as `.agents/rules/filing.md`, "Identity: the fingerprint",
gives it. `<symbol-or-concept>` names the symbol or concept, and `<kind>` is
a kind of the catalogue.

## Report

The seven parts of `.agents/rules/filing.md`, "The report". Strongest
rejected also names the candidates the catalogue's protected list killed.
