# Text residue: what a generator leaves behind

What a code generator leaves behind and a person would not have written on
purpose. Where agents write much of the code, residue is expected. This file
makes it a defect with a measurement instead of a matter of taste. Its
readers are the text-residue police, the court trying its findings, and any
reviewer of this repository's text. Everything a linter decides belongs to
the gate (`.agents/rules/verification.md`), not here.

## The one test

> Does this text carry a fact a reader cannot get from the text or the code
> beside it, in the same file?

It applies to a comment, a doc comment, a name and a test name. It also
applies to an error or log string, a pipeline step name and a paragraph of
the docs.

- No fact left over is noise. A false fact is a lie.
- Judge the sentence, not the block. A comment that states a reason and adds
  one empty sentence is a reason, not a finding. So is a reason with a hedge
  inside it.
- One excerpt can hold several findings. Each finding has exactly one kind.
- When two kinds fit, the later one in the list wins, because its
  measurement is stronger evidence.

## The kinds

| # | Kind | What it is | Measurement |
| :-- | :-- | :-- | :-- |
| 1 | `noise` | Text with no fact: a doc comment that rephrases the name, narration ("now we clear the buffer"), process commentary ("updated to", "as requested"), hedges ("should work"), reassurance words ("robust", "gracefully", "properly") standing in for a fact. In prose: a paragraph restating the one above, a sentence that exists to make a section look complete, or a package description repeating its name. **The forced-text seam:** where a lint forces a doc comment to exist, noise breeds there. The lint decides that a sentence exists, not that it says anything. The fix is the fact, never deletion: what the value means, which invariant holds, or when it is absent | The content words against the text and code beside them, with nothing left over. A restated paragraph: both paragraphs quoted. For a cluster: N comments across M files |
| 2 | `lying` | Text that contradicts the code: a name false since a rename, a comment for a branch that no longer exists. It also covers a doc comment promising what the body does not keep, a test name claiming more than the body checks, a step name the step does not perform, and a number nobody re-measured after the tree moved. A false claim about an outside system or a released artifact is not this kind. It is judged under `.agents/rules/claims.md`, and it is the graver of the two | The two quotes side by side, with the commit that wrote the text and the commit that changed the code under it |
| 3 | `naming` | A name that says nothing about the job: generic (`data`, `tmp`, `helper`, `result` where the value has a name), filler suffixes (`Manager`, `Helper`, `Utils`, `Impl`). It also covers the type's name stuttered into every member, and one concept under three names. A name fixed by a stored key, a serialization field, a published specification or an outside system's documentation is quoted, not chosen. It is not a finding | The census: every name for the concept with its file and line. For a generic name: its job in one sentence beside it, and the count of declarations with the same pattern across 3 or more files |
| 4 | `ceremony` | A test that cannot fail: an assertion on a fake's own configured return, a fixture asserted equal to itself, a tautology. It also covers a test that re-implements what it checks, and an assertion the type system already refuses. A frozen-answer test that any arithmetic change reddens is not ceremony. **A gate check or pipeline step** that could never fail on any tree it will see, with no reason beside it, is ceremony too. A check that duplicates a published schema or an upstream validator states which of two reasons keeps it: it enforces what the schema cannot express, or it turns a rejection into a message someone can act on. A duplicate with neither reason is ceremony | The mutation of the production code that leaves the test green, written out in full. For a check: a planted violation it ought to refuse, run through it in a copy under `$RUN`, with what it printed. Or the reason it can never fire, written out |
| 5 | `residue` | What the process left behind: changelog in comments ("now also", "no longer", "as before" with nothing after it), attribution of a tool, debug output, a compatibility alias nothing calls. It also covers `_v2` beside `_v1`, a scenario duplicated under a second name, and a test that guards a decision the repository no longer holds. In prose: a paragraph describing the change that introduced it instead of the thing, a section kept for a component or supported surface that is gone, and a reference file nothing links. In the fleet's own text, a date | The version-control search for the commit that brought it and the commit that made it moot. For what was moot on arrival: the introducing commit and the statement that nothing ever used it |

## Protected: never a finding

1. **Recorded reasons.** A comment stating why a shape exists, which
   invariant holds, or which trade was chosen. These include module headers
   that argue their design, the note beside a narrow lint suppression, and
   the reason required beside hand-rolled code. Other roles read these as
   evidence. The protection covers the reason. A claim of fact inside a
   reason is still judged against the code: protecting reasons wholesale
   would let a recorded invariant the code no longer holds escape the check
   built to catch it.
2. **Test sensitivity notes**: the `Stated sensitivity: … → RED` lines a
   regression test carries under `AGENTS.md`, "Tests must be able to fail".
3. **House style:** capitalised emphasis (NOT, ONLY, NEVER), em-dashes, long
   doc comments, numbered comments that state an ordered protocol.
4. **The owner's decisions, quoted** in the owner's own words and language.
   The language is part of the evidence.
5. **Text outside English on purpose.** Recognising and cleaning mixed
   Russian and English speech within one utterance is the product
   (`AGENTS.md`, "Non-negotiable principles", 6). So Russian text, alone or
   mixed with English, is deliberate in product prompts and examples under
   `Sources/SlovoCore/`, in test inputs under `Tests/` and `Tools/`, in the
   benchmark dataset under `Benchmarks/cleanup/`, and in quoted material
   under `docs/references/`. The Glagolitic glyph letters `AGENTS.md`,
   "Product intent — how the app must work", names are product text.
6. **Test input:** planted junk in fixtures, and any value a rule has to be
   exercised with. The `.swifttext` specimens under
   `Tests/GateChecksTests/Fixtures` are the gate checks' planted positive and
   negative cases. `Package.swift` keeps them out of the build graph, and
   `.swiftlint.yml` keeps them out of lint.
7. **Machine-written text:** `CHANGELOG.md`, which the release pipeline
   writes; the version fields of `Resources/Info.plist`, which the release
   pipeline stamps; `Package.resolved`, which the package manager writes. A
   wrong sentence there is judged at the code that writes it, or not at all.
8. **Model-written text that a person audits**, such as stored verdicts. Its
   wording is an audit question.
9. **A test name that reads as a sentence**, and a number quoted with its
   measurement beside it.
10. **The instructions:** `AGENTS.md`, everything under `.agents/`, the
    bindings under `.claude/agents/`, and `docs/architecture.md`. Read, never
    judged as text. Whether they agree with each other, and whether
    `docs/architecture.md`'s claims still hold, is the agent police's subject
    alone. Instruction text the product ships, such as the cleanup prompt it
    sends to a model, is product text and is judged.
11. **A cited source beside a claim**: its kind, its pinned revision, and its
    clause number for a specification. To an outside eye these read as
    hedging. Each is a fact `.agents/rules/claims.md` requires.
12. **Vendored third-party text**: a verbatim copy whose text belongs to its
    publisher.

## The fence

- **No check keys on vocabulary.** Words have legitimate readings, and a
  scan cannot draw the line judgement draws. Almost every phrase has a
  legitimate use somewhere, and strict CI turns each hit into a build
  failure.
- **What is fenced is constructs**, each with the harm it does. Here the two
  `custom_rules` in `.swiftlint.yml` fence two:
  - a print-family call under `Sources/`: the logger redacts, standard
    output does not;
  - an empty `catch`: errors must reach the failure glyph. A reason inside
    the braces passes, and swallowing `CancellationError` is exempt.

  CI is strict, so each is a build failure.
- **The admission test for a fence rule.** A new rule passes all of these.
  The two rules above predate the test and have no fixture yet. A change to
  either adds one:
  - the construct does harm and has no legitimate reading;
  - it has zero hits on the whole tree;
  - a fixture holds positive cases and must-not-trip negatives;
  - the legitimate cousin is carved out. A rule keyed on the words a stub
    message begins with is a vocabulary rule in disguise.
- A legitimate exception is silenced inline for the next line, with the
  reason on the line above.
- Anything a fence names cannot exist on a green `main`. A report of it is a
  misread. Residue is judged strictly above the fence.
- A tell that recurs and could be matched by a pattern is a proposal in a
  report, never a check added on the spot.

## Neighbours

A shape is judged as its own class of defect, not as residue: see
`.agents/rules/filing.md`, "Ownership routing". Residue names the text.
`ceremony` is only the test or gate check that cannot fail.

This file describes the fence in `.swiftlint.yml` and the files the release
pipeline and the package manager write. Where those disagree with it, they
win and this file is stale.
