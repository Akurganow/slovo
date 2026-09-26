# Tests: what a test must earn

What a test here must earn beyond being able to fail. Read by whoever
writes or changes a test here and by any reviewer of one, a person or an
unattended run. The first rule is AGENTS.md's, "Tests must be able to
fail", and it stays there; this file is the rest. Every § below is a
section of `docs/references/testing-swift.md`, which holds the sources:
they are cited, never restated.

## The one test

> Does this test fail only when the product is wrong, and is what it
> costs in proportion to what only it protects?

The product is wrong when it breaks a contract — AGENTS.md, the docs, or
the code's own stated promise — and each such break, written out as an
edit to the product, is a mutation. What a test protects is the set of
mutations that turn it red; what only it protects is the part of that set
no other test catches. What it costs is its lines, its upkeep, and every
red it shows with nothing broken.

## Writing a test

Each rule carries its reason; where the reason is long, the section named
carries it.

- **Test the decision at the cheapest point that makes it** — a value, a
  pure function, a reducer — not the rendered pixel, the source text or
  the clock. A heavier point runs the platform along with the decision,
  and fails when the platform moves (§2.6).
- **Assert the requirement and no more**: a tolerance, a range or a
  property where the requirement is one; exact only where exactness is
  the requirement. A stricter assertion fails on output the product is
  right to give (§2.4), and Swift Testing has no tolerance comparison, so
  the tolerance is written out and justified by the computation (§1.5).
- **Control every input.** Pass the clock in; wait on a state or a
  confirmation, never on a sleep; call a real system service only in the
  one designated test of its seam, gated with its reason stated. An input
  the test does not control hands its result to the machine, the load or
  the order (§1.3-1.4, §2.1).
- **Never mutate process-global state** — the environment,
  `UserDefaults.standard`, the working directory, statics. Tests run in
  parallel in one process, and `.serialized` orders only its own suite,
  never against another, so inject what the code reads (§1.2-1.3).
- **A platform's values are the platform's** — system colours, fonts,
  renderer output. Assert the app's choice, not how the platform draws
  it: those values change between releases and settings with no change
  to the app (§2.6).
- **Before adding a regression test, find the test that should have
  caught the bug.** Sharpen it when it exists; add a test only for a
  scenario no test holds. A second test beside one that nearly held the
  case is redundancy born with the fix (§2.3, §2.7).
- **A source guard only where no behavioural seam exists.** A source
  guard is a test that reads production source as text and asserts on
  it. Write the missing seam's reason in the file, and pin the contract
  rather than incidental text: a guard over incidental text fails on
  edits that change no behaviour (§4.2, §2.2).
- **A change that moves a test's protection elsewhere retires the test in
  the same commit.** It is AGENTS.md's directive 2: legacy dies in the
  commit that makes it legacy.

## The kinds

What a review files, and for the Test Police the whole definition of a
finding. Each kind is a way a test that can fail costs more than it
protects, and each comes with its measurement: no measurement, no
finding.

1. **`environment-coupled`** — the outcome depends on an input the test
   does not control: the OS or toolchain, a renderer, a system service,
   locale, the clock, scheduling, or process-global state other tests can
   touch. Measurement: the uncontrolled input traced to the assertion,
   and two environments or schedules under which the result differs,
   each a CI run or an official document; before blaming the test, show
   the nondeterminism is not the product's.
2. **`change-detector`** — it pins implementation text or structure where
   a behaviour or the compiler already guards the contract. Measurement:
   a behaviour-preserving edit, written out, that turns it red, and the
   behaviour test or compiler check that already guards the contract.
3. **`redundant`** — every mutation it catches, another test catches.
   Measurement: the protection ledger — each mutation it catches (from its
   sensitivity note and body) with the other test that goes red on it.
4. **`over-specified`** — the assertion demands more than the
   requirement: exact where the requirement is a property, a tolerance or
   a range. Measurement: the requirement quoted, and an output that meets
   it and fails the assertion.
5. **`disproportionate`** — its machinery (a rendered pixel, parsed
   source text, the wall clock, a real system service) is heavier than
   the contract it guards, and a cheaper point in the app already makes
   the decision it checks — so the extra weight checks the platform.
   Measurement: the contract in one sentence, quoted; the line that makes
   the decision; the smallest test that guards it, written out, caught by
   the same mutation of that decision; and the ways the current test
   fails with no change to the app.
6. **`bloat`** — a file or cluster grew without a matching contract: more
   tests, lines or helpers than the contracts they pin. Measurement: for
   a file or cluster, two measured columns — the cost (tests, lines,
   helpers, edits in commits that changed no behaviour) and the
   protection only these tests provide.

One finding has one kind: where two fit, it takes the one whose
alternative is the fix it proposes. A sensitivity note is evidence of what
its test claims to catch, and a note that names a behaviour-preserving
edit as the breakage it catches is a `change-detector` exhibit. A test
born with a fix is judged by these kinds against what later commits did to
the code it pins; "it never failed" is never grounds on its own. Where no
Apple toolchain is present, a conclusion that only a build or a run would
settle — that a mutation turns a test red, that a replacement compiles —
is `plausible`, never `confirmed` (`.agents/rules/unattended.md`).

## No protection lost silently

A removal names, for each mutation the test catches, the test that still
catches it; what nothing else catches is kept or replaced (§2.3, §2.5). A
replacement answers to this file like any other test: one written only to
catch a named mutation can pin the implementation instead, and is then a
`change-detector` of its own (§2.2).

## What is protected

Never a finding:

- **A test whose contract is the source text itself.** A gate that scans
  the tree for what must never, or must always, be written there. The
  text is the requirement, so reading it is the cheapest point that
  decides it. A test that reads source to reach a behaviour is a source
  guard, and the rules above judge it.
- **A probe that exists to prove a gate can fail.** A planted specimen,
  and the test that checks the gate catches it, are the gate's own proof
  under AGENTS.md's first rule.
- **A test gated off CI with a stated reason.** The trade is declared:
  CI never runs it, on purpose. Whether skipping it leaves what the test
  guards with no signal in CI can still be an `environment-coupled`
  finding, with that kind's measurement.
- **The platform, tested on purpose** — the one designated test of a
  platform seam, named as such in the test; a visual result that is itself
  the requirement and that no cheaper point in the app decides; a platform
  behaviour that has broken the product before, on record. A real
  dependency that breaks the product is a signal, not noise (§2.6).
- **Exactness or an implementation detail that is itself the
  requirement** — a prompt sent verbatim, a byte-exact wire format, a
  call count or order with side effects. Loosening the assertion would
  let a real change through.
- **Duplication kept for clarity** — setup repeated so each test reads
  alone, or tests left apart because merging them would be harder to
  read (§2.5).
- **A distinct regression input.** A test that feeds a case no other test
  feeds is not `redundant` because another test runs the same lines:
  redundancy is measured by the mutations caught, never by coverage
  (§2.3).
- **A shape with a recorded reason.** A comment, rule or document stating
  why the test takes the form it has, or which trade AGENTS.md chose.
  Other reviews read these as evidence, and the reason protects the shape
  for as long as what it states is true.
- **Sensitivity notes, as prose.** The "Stated sensitivity: … → RED"
  lines AGENTS.md requires are never judged as writing
  (`.agents/rules/slop.md` protects them too); what a note claims is
  evidence under the kinds above.

## Neighbours

Which role owns a finding is the table in `.agents/rules/tracker.md`. A
test that cannot fail is `ceremony` (`.agents/rules/slop.md`), not a kind
here. A test's name and doc comment are the Slop Police's, and so is a
scenario duplicated under a second name, which is `residue` and never
`redundant`: `redundant` is a different scenario whose every mutation
another test catches. A helper or other abstraction under `Tests/` is
judged here, as `bloat` or under the kind its cost fits; the Abstraction
Police's row stops at `Tests/`. A test of code that is itself dead or
vestigial goes with that code. A product defect a test reveals is the
Logic Police's: a test that is red for a reason the product has is doing
its job.
