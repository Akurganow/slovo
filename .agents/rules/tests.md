# Tests: what a test must earn

What a test here must earn beyond being able to fail. Its readers are
whoever writes or changes a test, and every reviewer of one, a person or an
unattended run. The first rule, "Tests must be able to fail", is in
`AGENTS.md` and stays there; this file is the rest. Every § below is a
section of `docs/references/testing-swift.md`, which holds the sources.
Sources are cited, never restated.

## The one test

> Does this test fail only when the product is wrong, and is what it costs
> in proportion to what only it protects?

- **The product is wrong** when it breaks a contract: `AGENTS.md`, the docs,
  or the code's own stated promise.
- **A mutation** is such a break, written out as an edit to the product.
- **What a test protects** is the set of mutations that turn it red.
- **What only it protects** is the part of that set no other test catches.
- **Cost** is its lines, its upkeep, and every red it shows with nothing
  broken.

## Writing a test

1. **Test the decision at the cheapest point that makes it**: a value, a
   pure function, a reducer. Not the rendered pixel, the source text or the
   clock. A heavier point runs the platform with the decision and fails when
   the platform moves (§2.6).
2. **Assert the requirement and no more.** A tolerance, a range or a property
   where the requirement is one. Exactness only where exactness is the
   requirement (§2.4). Swift Testing has no tolerance comparison, so the
   tolerance is written out and justified by the computation (§1.5).
3. **Control every input.** Pass the clock in. Wait on a state or a
   confirmation, never on a sleep. Call a real system service only in the
   one designated test of its seam, gated, with its reason stated
   (§1.3-1.4, §2.1).
4. **Never mutate process-global state**: environment variables,
   `UserDefaults.standard`, the working directory, statics. Tests run in
   parallel in one process, and `.serialized` orders only its own suite,
   never against another. Inject what the code reads (§1.1-1.3).
5. **A platform's values are the platform's**: system colours, fonts,
   renderer output. Assert the application's choice, not how the platform
   draws it (§2.6, §4.4).
6. **Before adding a regression test, find the test that should have caught
   the bug.** Sharpen it if it exists. Add a test only for a scenario no test
   holds. A second test beside one that nearly held the case is redundancy
   born with the fix (§2.3, §2.7).
7. **A source guard only where no behavioural seam exists.** A source guard
   reads production source as text. Write the missing seam's reason in the
   file. Pin the contract, not incidental text (§4.2, §2.2).
8. **A change that moves a test's protection elsewhere retires the test in
   the same change.** Legacy dies in the change that makes it legacy
   (`AGENTS.md`, "Standing owner directives", 2).

## The kinds

Each is a way a test that can fail costs more than it protects. No
measurement, no finding.

| # | Kind | Definition | Measurement |
| :-- | :-- | :-- | :-- |
| 1 | `environment-coupled` | The outcome depends on an input the test does not control: the OS or toolchain, a renderer, a system service, locale, the clock, scheduling, or process-global state other tests can touch (§1.2-1.4, §2.1) | The uncontrolled input traced to the assertion, and two environments or schedules under which the result differs, each a CI run or an official document; before blaming the test, show the nondeterminism is not the product's |
| 2 | `change-detector` | It pins implementation text or structure where a behaviour or the compiler already guards the contract (§2.2) | A behaviour-preserving edit, written out, that turns it red, and the behaviour test or compiler check that already guards the contract |
| 3 | `redundant` | Every mutation it catches, another test catches (§2.3, §3.1) | The protection ledger — each mutation it catches (from its sensitivity note and body) with the other test that goes red on it |
| 4 | `over-specified` | The assertion demands more than the requirement: exact where the requirement is a property, a tolerance or a range (§2.4) | The requirement quoted, and an output that meets it and fails the assertion |
| 5 | `disproportionate` | Its machinery (a rendered pixel, parsed source text, the wall clock, a real system service) is heavier than the contract it guards, and a cheaper point in the app already makes the decision it checks — so the extra weight checks the platform (§2.6) | The contract in one sentence, quoted; the line that makes the decision; the smallest test that guards it, written out, caught by the same mutation of that decision; and the ways the current test fails with no change to the app |
| 6 | `bloat` | A file or cluster grew without a matching contract: more tests, lines or helpers than the contracts they pin (§2.5) | For a file or cluster, two measured columns — the cost (tests, lines, helpers, edits in commits that changed no behaviour) and the protection only these tests provide |

The criteria table of `docs/references/testing-swift.md`, "5. The criteria a
review applies", repeats these definitions and measurements word for word and
records the sources behind each. This file is the authority, as the reference
itself states.

Cross-kind rules:

- One finding, one kind: the one whose alternative is the fix proposed.
- A sensitivity note is evidence of what its test claims to catch. A note
  that names a behaviour-preserving edit as its breakage is a
  `change-detector` exhibit.
- A test born with a fix is judged against what later commits did to the
  code it pins. "It never failed" is never grounds on its own (§2.7). A test
  that never failed may still guard a contract. Where its cost matters, run
  it less often instead of deleting it.
- Without the toolchain, "this mutation turns it red" and "the replacement
  compiles" are `plausible` (`.agents/rules/unattended.md`, "Claim only what
  you ran").

## No protection lost silently

A removal names, for each mutation the test catches, the test that still
catches it. What nothing else catches is kept or replaced. Redundancy is
measured by mutations caught, never by coverage: coverage-based suite
reduction loses real protection, mutation-based reduction does not (§2.3,
§2.5). A replacement answers to this file like any other test. One written
only to catch a named mutation can pin the implementation and become a
`change-detector` of its own (§2.2).

## Protected: never a finding

1. A test whose contract is the source text itself: a gate that scans the
   tree for what must never, or must always, be written.
2. A probe that exists to prove a gate can fail: a planted specimen and the
   test that checks the gate catches it.
3. A test gated off CI with a stated reason. It can still be
   `environment-coupled` if skipping it leaves its contract with no CI
   signal (§4.3).
4. The platform, tested on purpose, in three cases:
   - the one designated test of a platform seam, named as such;
   - a visual result that is itself the requirement;
   - a platform behaviour that has broken the product before, on record.
5. Exactness that is itself the requirement: a prompt sent verbatim, a
   byte-exact wire format, a call count or order with side effects.
6. Duplication kept for clarity: setup repeated so each test reads alone, or
   tests left apart because merging would hurt readability (§2.5).
7. A distinct regression input. A test feeding a case no other test feeds is
   not redundant because another test runs the same lines (§2.3).
8. A shape with a recorded reason, for as long as the reason is true. Only
   the test police's seam challenge argues that a reason no longer holds.
9. Sensitivity notes, as prose (`.agents/rules/text-residue.md` protects
   them too).

## Neighbours

Which role owns a finding is `.agents/rules/filing.md`, "Ownership routing".
A test that cannot fail is `ceremony`, and a scenario duplicated under a
second name is `residue`. Both are kinds of `.agents/rules/text-residue.md`,
not of this file.
