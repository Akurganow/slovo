# Slop: what generator residue looks like

What a code generator leaves behind and a person would not have written
on purpose. Read by any reviewer of this code, a person or an
unattended run; the deterministic part lives in `.swiftlint.yml`.

## The one test

> Does this text carry a fact a reader cannot get from the code beside
> it, in the same file?

A comment, a doc comment, a name, a test name, a log string, a README
paragraph: no fact left over is noise; a false fact is a lie. Judge the
sentence, not the block: a comment that states a reason and adds one
empty sentence is a reason, not a finding, and so is a reason with a
hedge or a reassurance word inside it. One excerpt can hold several
findings; each has one kind, and when two kinds fit, the later in the
list below wins — its measurement is the stronger evidence.

## The kinds

1. **`noise`** — text with no fact: a doc comment rephrasing the name
   (`/// The transcript` on `let transcript`), narration ("now we clear
   the buffer"), process commentary ("updated to", "as requested"),
   hedges ("should work") and reassurance adjectives (robust,
   gracefully) standing in for a fact. Measurement: the content words
   against the code beside them, nothing left over.
2. **`lying`** — text that contradicts the code: a name false since a
   rename, a comment for a branch that no longer exists, a doc comment
   promising what the body does not keep, a test name claiming more
   than the body checks. Measurement: the two quotes side by side.
3. **`naming`** — a name that says nothing about the job: generic
   (`data`, `temp`, `helper`), filler suffixes (`Manager`, `Helper`,
   `Utils`, `Impl`), the type's own name stuttered into every member,
   one concept under three names across files. Measurement: the
   census, every name for the concept with its file.
4. **`ceremony`** — a test that cannot fail: an assertion on a fake's
   own configured return, a tautology, a test that re-implements what
   it checks. AGENTS.md forbids these. Measurement: the mutation of the
   production code that leaves the test green.
5. **`residue`** — what the process left behind: changelog in
   comments, attribution of a tool, debug output, compatibility aliases
   nothing calls, `_v2` beside `_v1`, a scenario duplicated under a
   second name. Measurement: `git log -S` for when it arrived and what
   made it moot.

## What is protected

Never a finding:

- **Recorded reasons.** A comment stating why a shape exists, what
  invariant holds, or which trade AGENTS.md chose. Other reviews read
  these as evidence.
- **Test sensitivity notes.** The "Stated sensitivity: … → RED" lines
  AGENTS.md requires on regression tests.
- **House style.** Capitalised emphasis (NOT, ONLY, NEVER), em-dashes,
  long `///` doc comments, numbered comments that state an ordered
  protocol.
- **The instructions.** AGENTS.md, `.agents/rules/`,
  `docs/architecture.md`.

## The fence

Words have legitimate readings, so no lint rule keys on vocabulary.
The `custom_rules` in `.swiftlint.yml` name two constructs that do
harm here and have none: a print-family call under `Sources/` (the
logger is redaction-safe, stdout is not) and an empty `catch` (errors
must reach the glyph; a reason inside the braces passes, swallowing
`CancellationError` is exempt). CI is strict, so each is a build
failure; a legitimate exception is silenced with
`swiftlint:disable:next` and the reason on the line above.

## Neighbours

A shape is judged as its own class of defect, not as slop: a swallowed
error or hidden fallback with a reachable wrong result is a logic
defect; a guard for an impossible state or a mechanism out of
proportion is a proportion defect; a thin wrapper, a one-conformer
protocol or a duplicated helper is an abstraction defect. Slop names
the text; the shape is judged on its own terms.
