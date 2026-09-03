# Slop: what generator residue looks like

The catalogue of text and shapes that a code generator leaves behind and
a person would not have written on purpose. Two consumers read it: any
reviewer of this code, a person or an unattended analysis run, and the
`custom_rules` block in `.swiftlint.yml`, which fences the deterministic
part at the door. It is data, not policy: what counts as slop shifts with
the models, so the catalogue carries a date and is refreshed against
outside evidence (below), while the reviews and the linter stay put.

Catalogue date: 2026-09. Refresh when the generators change, roughly
twice a year.

## The one test

> Does this text carry a fact a reader cannot get from the code beside
> it?

A comment, a doc comment, a name, a test name, a log string, a README
paragraph: if the answer is no, it is noise; if it carries a fact that is
false, it is a lie. Everything else in this file is that test applied to
the places generators put text.

## The evidence behind it

Measured, not anecdotal, as of September 2026:

- The strongest stylometric signal separating generated from human code
  is the comment ratio; next come identifier length and naming
  consistency (SemEval-2026 Task 13; arXiv 2502.17749).
- Per-agent fingerprints over 33,580 pull requests: Claude Code shows
  high conditional density and elevated comment density; Codex long
  multiline commit messages; Cursor bullet-and-link PR bodies; Copilot
  long PR descriptions (arXiv 2601.17406).
- Block duplication per million changed lines rose from 40 (2023) to 73
  (2026), while refactoring fell from 21% to under 4% of changed lines
  (GitClear 2026). Generated code concentrates in test files and clones
  within a repository (arXiv 2607.01867).
- Generated tests: assertion roulette, magic-number tests, and
  tautologies that mock the function under test (arXiv 2410.10628).
- Deterministic detectors agree on the same short list: comments that
  restate or narrate, hedging, section banners, meta comments about the
  agent's own process, generic and versioned names, swallowed errors,
  hidden fallbacks, thin wrappers, stubs, tests that cannot fail
  (scanaislop/aislop, LeonardNJU/code-humanizer, yuvrajangadsingh/
  vibecheck, flamehaven01/AI-SLOP-Detector, JordanGunn/agent-slop-lint).
- Prose tells rotate every 12 to 18 months and differ by model family;
  a vocabulary list is stale on arrival (seyedehsanhadi/sloptrim).

## The kinds

Five, each with the measurement that makes a finding a finding.

1. **`noise`** — text that carries nothing: a comment restating the next
   line; a doc comment rephrasing the name (`/// The transcript` on
   `let transcript`); narration ("now we clear the buffer"); numbered
   steps that merely count statements; banners; process commentary
   ("updated to", "as requested", "this change adds"); hedges ("should
   work", "for now"); reassurance adjectives (robust, gracefully,
   properly, simply) standing in for a fact; README boilerplate that
   describes the update instead of the thing. Measurement: the text's
   content words against the code beside it, with zero facts left over.
2. **`lying`** — text that contradicts the code: a name that stopped
   being true at a rename, a comment describing a branch that no longer
   exists, a doc comment promising a guarantee the body does not keep, a
   test name asserting more than its body checks, a README claiming
   behaviour the app does not have. Measurement: the two quotes, side by
   side.
3. **`naming`** — names that say nothing about the job: generic
   (`data`, `result2`, `temp`, `helper`), filler suffixes (`Manager`,
   `Helper`, `Utils`, `Impl`), versions (`V2`, `New`) coexisting with the
   original, the type's own name stuttered into every member, and
   synonym drift: one concept under three names across files.
   Measurement: the census — every name for that concept, with its file.
4. **`ceremony`** — tests that cannot fail: an assertion on a fake's own
   configured return; a tautology; a test with no `#expect` or
   `#require` whose body cannot throw or trap; magic numbers asserted
   against magic numbers; a test that re-implements the code it checks.
   AGENTS.md already forbids this ("tests must be able to fail").
   Measurement: the mutation of the production code that leaves the test
   green, written out.
5. **`residue`** — what the process left behind: changelog in comments,
   diff-anchored docs, attribution of the tool in source, debug output,
   untracked TODO stubs, compatibility aliases nothing calls, `_v2`
   beside `_v1`, the same test scenario under a second name, a file
   created because editing the old one was harder. Measurement:
   `git log -S` for when it arrived and what made it moot.

## What is protected

Never a review finding, whatever the detectors say:

- **Recorded reasons.** A comment that states why a shape exists, what
  invariant holds, or which trade AGENTS.md chose. Every other review
  of this code reads these as evidence; removing them removes evidence.
- **Test sensitivity notes.** AGENTS.md requires every regression test to
  document the concrete breakage it catches; the tests phrase it as
  "Stated sensitivity: … → RED". Dense, capitalised, deliberate.
- **House style.** Capitalised emphasis (NOT, ONLY, NEVER), em-dashes,
  long doc comments in `///`, numbered comments that state an ordered
  protocol rather than count statements. Prose detectors flag all of
  these; here they are the owner's voice.
- **The instructions themselves.** AGENTS.md, `.agents/rules/` and
  `docs/architecture.md` are read, never judged.

## The fence: what the linter owns

Slop is ephemeral: what counts shifts with the generators, and almost
every phrase a generator overuses has a legitimate reading somewhere —
"for now" in a recorded deadline, a model name in a comment about the
cleanup step, `Manager` on a type that wraps one. A deterministic gate
that keys on vocabulary therefore blocks legitimate text sooner or
later, and CI here is strict, so a warning is a build failure. The
`custom_rules` in `.swiftlint.yml` name no words. They name constructs
that have no legitimate reading in any year: a line that is only a
separator, a print-family call under `Sources/` (the logger is
redaction-safe; stdout is not), an empty `catch`, an expectation that
cannot fail (`#expect(true)`, `x == x`), a trap whose message says the
code is unfinished, a test with no body.

Everything phrased in words — hedges, change narration, attribution,
filler names, vague error strings — is judged by a reader against the
one test above, never by a regex. A shape that recurs and has no
legitimate reading is a proposal for a new rule.

## Neighbours

Slop that is a shape rather than text is a different class of defect
and is judged as such, not as slop: a swallowed error or a hidden
fallback with a reachable wrong result is a logic defect; a guard for an
impossible state or a mechanism out of proportion to its job is a
proportion defect; a thin wrapper, a single-implementation protocol, a
duplicated helper or a reinvented dependency is an abstraction defect.
Slop names the text; the shape is judged on its own terms.
