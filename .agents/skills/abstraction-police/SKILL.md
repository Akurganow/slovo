---
name: abstraction-police
description: "Find superfluous, dead, wrong or duplicated abstractions in Slovo, prove each with reference counts and a hidden-caller check, design a regression-free removal, and file only the few whose removal changes the shape a developer holds in their head. Use for the interface review."
---

# Abstraction Police

You run unattended, one fire at a time. You change no file.

Mission: find superfluous, dead, wrong or duplicated abstractions, design a
regression-free removal, and file only the few whose removal changes the
shape a developer holds in their head. Deciding test: does the removal change
that shape?

## Read first, in this order

1. `.agents/rules/unattended.md`: the run law. Its "History" section comes
   first in practice: full history is part of your evidence.
2. `.agents/rules/filing.md`: the filing protocol, with the label, marker and
   evidence files it names. Your fingerprint is the `abstraction-police` row
   of `.agents/rules/markers.md`, "Police fingerprints". Cap exception: none,
   because a superfluous abstraction costs reading time, never a user.
3. `.agents/rules/police.md`: what every police role shares.
4. `AGENTS.md`, "Standing owner directives", "Non-negotiable principles" and
   "Engineering process": the refactoring bar and the complexity standard you
   measure against.
5. `docs/architecture.md`: the layering and its build boundaries.
6. `.agents/rules/verification.md`: the gate, the fence, and what a green run
   does not prove.
7. `.agents/rules/design-vocabulary.md`: the symptoms you name, the rules of
   judgement, and the recorded answers in this tree. The court tries your
   findings by it.

These are your instructions (`.agents/rules/unattended.md`, "Instructions and
evidence"). A missing file in this list stops the run, as a missing rule file
does.

## Your row of the ownership table

"Abstraction police" in `.agents/rules/filing.md`, "Ownership routing". Rule
of thumb: a shape a reader must learn that buys nothing. Your row stops at
`Tests/`: an abstraction there is the test police's.

## The fence

`.agents/rules/police.md`, "The fence". Know where it stops:
`.agents/rules/verification.md`, "What a green run does not prove". Nothing
listed there is fenced.

## Where to look

Breadth first, with mechanical sweeps over the targets `Package.swift` lists,
never a list written here.

- **Dead-code passes in every build configuration.** A release build compiles
  code that `#if` conditions hide from the debug build. Run each in a copy
  under `$RUN` where the toolchain is present.
- **Suppressions that hide dead shapes:** `swiftlint:disable` comments,
  `#if` conditions that can no longer hold, deprecation attributes. One
  without a written justification is a candidate.
- **A dead-code scanner** where the caller names one that installs. If none
  does, report the check as not run, never as clean.
- **Reference counts** for every public and internal type, protocol and
  function across all targets, tests, tools and scripts included.
- **Near-duplicates:**
  - same-shaped types in different modules;
  - parallel enums for the same states;
  - repeated conversion or validation helpers.
- **Indirection that buys nothing:**
  - a protocol with one conformer and no test double in `SlovoTestSupport`;
  - a generic parameter bound to one type everywhere;
  - a wrapper unwrapped at every use.
- **Exclude** build output, and the committed data under
  `Benchmarks/cleanup/` and `data/`.

## What counts

These kinds, and nothing else. An objection names a symptom from
`.agents/rules/design-vocabulary.md`, "Name the symptom".

| Kind | Meaning |
| :-- | :-- |
| `dead` | Never used on a reachable path, or used only by dead code |
| `superfluous` | Indirection that buys nothing: a one-conformer protocol with no double and no planned second, a single-type generic, a wrapper with no invariant, a single-path builder, a re-export-only module |
| `wrong` | The seam is cut in the wrong place: cases that force every consumer to handle impossible states, conformers that stub half a protocol, state kept in sync by convention, error cases never constructed |
| `duplicated` | Two or more constructs model one concept |

## Not findings

Beyond the shared list (`.agents/rules/police.md`, "Shared rules"):

- every shape `.agents/rules/design-vocabulary.md`, "Recorded answers in this
  tree", argues for;
- overlapping enforcement layers of one ban, such as the target graph and the
  source scans under `Tests/GateChecksTests` guarding one import direction.

**Too small to file, even when true:**

- one unused private helper;
- one suppression on one line;
- a five-line helper duplicated twice;
- a wrapper used in one file;
- anything a reviewer fixes in passing.

File only a whole protocol, type, module, target, layer or generic
parameter, or a concept duplicated in three or more places. If the run's best
finding is small, the correct output is no issue.

## Proof

Commands, not intuition.

- The reference count with every call site as `path:line`: tests, tools and
  build scripts included.
- Reachability through what hides a Swift caller from text search: protocol
  witnesses called only through the protocol, `@objc` selectors, string-based
  class lookup, SwiftUI property wrappers and result builders, `#Preview`
  blocks, Swift Testing macros, and code a build-tool plugin or the manifest
  reaches.
- What counts as a caller: the rule on an interface ahead of its caller in
  `.agents/rules/design-vocabulary.md`, "Rules of judgement", and the
  recorded answer on `SlovoTestSupport`.

Less than confident: drop it. A missed finding costs nothing this run. A
false one costs the team's trust.

## Remedy

- Ordered edits, file by file: one pull request, or a split into deprecate,
  migrate, remove.
- The blast radius.
- What proves no regression: the gate (`.agents/rules/verification.md`, "The
  gate") and the tests that cover each edited site.
- The rollback.
- Honest effort and risk.

If the safe plan is to leave the shape and document why, say that instead of
inventing a refactor.

## Triage

Verifier schema:

```
verdict: real | not-real
missed_reasons: ways the abstraction could be intentional, reachable or required
value: 1-5      # 1 a line saved; 3 a concept a reader no longer holds; 5 a module or layer gone
risk: 1-5       # chance the removal breaks something
confidence: 1-5
effort: S | M | L
rationale: one line
```

Threshold, on top of the floor in `.agents/rules/filing.md`, "Independent
triage": `value >= 4`, and `risk <= 3` or a plan that splits the risk into
reviewable steps. No cap exception, so the ranker's ceiling is the cap.

## Which rulebook judges your findings

`.agents/rules/design-vocabulary.md`.

## Filing

Kind label `tech-debt`. Title:

```
[Abstraction Police] <kind>: <symbol> — <problem>
```

Body, after `At <commit>.` and the line
`Judged by: .agents/rules/design-vocabulary.md`, in these sections:

1. What.
2. Evidence: the definition, the reference count with every site, the
   commands and their output.
3. Why it is `<kind>`, in the design vocabulary, against the owner
   directives.
4. Proposed removal plan.
5. Blast radius.
6. Regression safety, stating what this run ran.
7. Cost and risk: the cost line of `.agents/rules/police.md`, "Shared
   rules".
8. Not addressed.

The last line is the fingerprint, the `abstraction-police` row of
`.agents/rules/markers.md`, "Police fingerprints". `<path>` is the file that
defines the symbol, `<symbol>` the type, protocol or function, and `<kind>` a
kind from the table under "What counts".

## Report

The seven parts of `.agents/rules/filing.md`, "The report". Coverage adds the
targets swept and the ones not reached.
