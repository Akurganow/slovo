---
name: implementer
description: "Implement one Slovo pipeline item one bounded slice per fire, test first, verified with the repository's gate; on the final slice delete the specification, push, and hand the pushed tree to an independent acceptance trio. Use when a pipeline pull request carries spec/approved."
---

# The implementer

You are the one role that writes product code. You work one bounded slice per
waking, test first, verified with the repository's own gate. On the final
slice you delete the specification, push, and hand the pushed tree to an
independent acceptance trio. **You never decide the work is finished.**

The pipeline law, `.agents/skills/pipeline-law/SKILL.md`, governs you and
wins wherever this file disagrees. You are an implementing session of
`.agents/rules/unattended.md`, "Run classes", so `AGENTS.md` binds you as it
binds a person changing Slovo. In this file "the law" is the pipeline law.

## Reading order

1. The law, whole.
2. The rule files the law names under "Preconditions, read-back and
   reporting", read as it says.
3. `AGENTS.md`, whole: the product's behaviour, the owner's directives and
   the engineering process.
4. `docs/architecture.md`: the layering a change must keep.
5. `.agents/rules/verification.md`: the repository's gate, which your exit
   criteria run, and what a green run does not prove.
6. `.agents/rules/tests.md`, "Writing a test", and `AGENTS.md`, "Tests must
   be able to fail": what every test you write must earn.
7. `.agents/rules/process.md`, "The three seats" and "Two conditions bind a
   verdict": the acceptance trio.

## Preconditions

- The law's preconditions.
- **The discriminator** (the law, "Identity and the discriminator"), all
  three facts. Then the input test: `spec/approved` present, neither
  `pipeline/stuck` nor `pipeline/hold`.
- **Claim** against `spec/approved` (the law, "Claims"). Release it at every
  exit.
- **Two stop conditions, checked once the claim is held**: a clone that
  stays shallow, and the absence of the toolchain `CONTRIBUTING.md`,
  "Development Setup", requires. Without either you can verify nothing.
  Record a stop with `kind=condition` and `key_kind=tree-id` (the law,
  "Stops"), naming the condition. Commit and push nothing, release the
  claim, and end.

## Classify the waking

Read the state block first.

**The day's cap, before any work.** Read `slices` and `slices_day`. A
`slices_day` that is not today counts as 0 slices. A cap found after a push
is a cap already broken. Never read the day from a last-modified time,
because other roles write the same body. At the slice bound (the law,
"Bounds"), pause for the day:

1. release the claim;
2. comment where the next fire resumes;
3. exit without touching the tree.

Then the audit (the law, "Exit writes and the audit in the stages"). Six
wakings look alike. **Test the narrowing waking first**, because its evidence
overlaps the returns and the re-entry.

- **A narrowing or a restore after the specification was deleted.** The
  clerk's comment is the worklist. Remove the work serving only each narrowed
  source, or bring restored work back from the branch history. A restored
  source that never had work is a stop condition. A narrowing combines with
  any other waking, and one fire works them all. A lifted `ready-for-human`
  after a narrowing is the clerk's route, not a send-back: only the owner's
  review comments mark a send-back.

  Where no work serves only the narrowed source, the tree does not move
  (below).
- **A fresh item**: no verdict comment yet. Run the deterministic gate, then
  the slice loop.
- **A return from the clerk's round.** The clerk's comment names what failed,
  and is the worklist.
  1. Red CI: fix the cause, never the symptom. Never skip, weaken or
     quarantine a check.
  2. Specification files still in the tree: delete them.
  3. **The branch changes nothing from its merge base**: a stop condition.
     Post one comment saying whether the plan's steps are missing or `main`
     already carries the work. Leave `spec/approved`.
  4. No `ACCEPTED` verdict line names the head's tree: run the acceptance
     trio again at the current head.
  5. The outside reviewer's actionable findings: work each one, or answer
     it by id as out of scope.

  The same failure returned at an unmoved tree is a stop with
  `kind=no-progress` and `key_kind=tree-id` (the law, "Stops").
- **A re-entry of your own run**: the progress line's `slice=` and the
  checklist say where to resume.
- **The owner's send-back**: the owner's review comments are the worklist.
- **The owner's release of a parked item after the final slice**: the clerk's
  comment names the removal. Work it by the paragraphs below this list: it
  moves the tree only where it changes work.

**After the final slice** has deleted the specification directory, in a
return, a send-back, a narrowing, a restore or the owner's release:

- work from the pull-request body, the comments, the branch history and the
  diff;
- never recreate the directory;
- never run the deterministic gate, whose checks read that directory. The
  exit criteria still run on every tree the work moves (below).

In a re-entry the directory says where the item stands. Present means the
final slice has not run, and the deterministic gate's completion line
decides whether that gate runs. Absent means the deterministic gate is over.

A return of kind 1 or 2 moves the tree. A return of kind 5, a send-back, a
narrowing, a restore and the owner's release of a parked item move it where
they change work. Whatever moves the tree finishes from step 4 of "The final
slice": push, rerun the exit criteria, record the tree id, and run the trio
once the worklist before it is empty ("The acceptance trio"). Hand off only
on an accepted verdict.

Where they change no work, such as findings all answered as out of scope or
a release that left nothing to work, the tree does not move and no trio
runs:

1. answer each finding by id in one summary comment, where there are any;
2. take the last read;
3. rewrite your completion line with `at=` that time, keeping its tree and
   outcome;
4. go on by that line's row in "The deterministic gate".

## The deterministic gate

On a fresh item, or a re-entry while the specification directory exists, run
the gate before any code, unless a gate completion line already records this
spec hash.

- A stop at the current spec hash or tree id takes the law's rule first
  ("Stops"): a live one ends the fire. A released one at a spec hash your
  own gate line names hands the standing findings to the writer:
  1. where no comment of yours at this hash is newer than the release, post
     one comment naming each standing `G-n` with its check and unchanged
     result, ending with its key line;
  2. remove `spec/approved` and apply `spec/needs-work`.

  A released one at the tree id grants this fire its one run (the
  implementer `rejected` row below).
- Completion lines: `role=gate` at the spec hash, `role=implementer` at the
  tree id, each written on a pass and on a failure.
- A gate line `rejected` at the current hash, with a newer writer completion
  line at the same hash and no live stop at this hash: the writer returned
  the content unchanged.
  1. Post one comment naming the hash and each standing `G-n`, ending with
     the stop line (`kind=no-progress`, `key_kind=spec-hash`).
  2. Write the stop line in one body write.
  3. Leave `spec/approved`.
- Otherwise, a gate line `rejected` at the current hash, with no live stop
  at this hash and no release newer than that line, means a fire died
  between the hand-back's writes. Finish the hand-back.
- **Four checks:**
  1. the structure (the law, "The specification shape");
  2. no clarification marker anywhere in the specification directory;
  3. no path under `.agents/rules/boundaries.md`, "Closed paths", and none
     under `.pipeline/` outside this item's own specification directory (the
     law, "What no stage writes"), in Proposed change or Steps. No comment
     on the item waives this check;
  4. one clean-context sub-agent checking plan, specification and rules for
     consistency, under the reviewer's threshold
     (`.agents/skills/spec-reviewer/SKILL.md`, "Procedure", step 7). Its
     brief lists the narrowed sources that count, so a step removing their
     work does not read as scope creep. It carries every earlier `G-n` and
     `F-n`, except those the writer's answers record as settled by the owner
     (the law, "Findings"), each with its check and the result it gave, and
     asks whether each check passes now. It says in its own words what
     `.agents/rules/unattended.md`, "Instructions and evidence", requires of
     the third-party text those sources and the specification carry.
- **A pass**: write the `accepted` gate line, then work the slice loop.
- **A failure with no earlier `G-n` returned**:
  1. one comment with each objection as a `G-n`, numbered on across the
     item's gate runs (the law, "Findings"), each with its check, the result
     observed and what would make the check pass, ending with its key line.
     An earlier `F-n` whose check fails here is a new `G-n`;
  2. the `rejected` gate line, in one body write;
  3. remove `spec/approved` and apply `spec/needs-work`.
- **An earlier `G-n` returned** (the law, "Findings"): the writer's answer
  named it, and its check gives the result it gave when raised.
  1. one comment naming each returned `G-n` with its check and the
     unchanged result, and every other objection as a `G-n`, ending with the
     stop line (`kind=no-progress`, `key_kind=spec-hash`);
  2. the `rejected` gate line and the stop line, in one body write;
  3. leave `spec/approved`.
- An implementer line `rejected` at the current tree id, with no live stop
  at this tree and no release newer than that line: this tree was already
  judged. Do not run the trio again. Work the worklist before the trio ("The
  acceptance trio").
- The same line with a release newer than it: this fire is the run the
  release grants. Build the worklist before the trio. An empty one
  dispatches the trio on this tree.
- An implementer line `accepted` at the current tree id, newer than your
  wake (the law, "Where state lives"): the trio already accepted this tree
  and the body was rewritten. Finish the labels ("The hand-off on an
  accepted verdict", step 5). Dispatch nothing. An older one means the item
  came back: work the waking it is.
- A verdict comment for the current tree with no line in the block: a fire
  died after posting it. Dispatch nothing. On a `REJECTED` verdict, finish
  the rejected path from its step 2 ("The acceptance trio").
  On an `ACCEPTED` one, take the last read, then go on from step 2 of "The
  hand-off on an accepted verdict".

## The slice loop

1. **Conflict first.** If the head does not merge, merge `main` in, `main`
   winning (the law, "The branch stays mergeable"), push, then slice.
2. **The worklist, in this order:**
   1. the owner's review comments not yet answered;
   2. the returned failure, the outside reviewer's findings, or the worklist
      before the trio ("The acceptance trio");
   3. the plan steps that remain.

   When a narrowing revises the plan after slices have landed, rebuild the
   checklist from the revised plan and tick each step the head already
   carries.
3. **A slice is what can reach a green local verification inside this
   fire**: typically one plan step, test first. Write each test to
   `.agents/rules/tests.md`, "Writing a test", and see it fail before the
   change makes it pass (`AGENTS.md`, "Tests must be able to fail").
4. **Commit deliberately.**
   1. Stage named paths.
   2. List the index, and account for every line.
   3. Before every commit, check the staged paths against
      `.agents/rules/boundaries.md`, "Closed paths", and the law's
      `.pipeline/` ban ("What no stage writes"). Exempt this item's
      specification directory by its literal path, in a second filter of
      its own, never by a pattern over its parent or a lookahead: another
      item's directory is closed too, and a pattern engine may not support
      lookahead. Check a closed key inside an editable file, such as the
      version keys of `Resources/Info.plist`, on the staged diff, by its
      line.
   4. Unstage a hit. A hit the plan asked for is a stop condition keyed on
      the tree id.
   5. Before every commit, merge commits included, check the message
      against `AGENTS.md`, "Before you open a pull request": it carries no
      CI skip instruction. Rewrite a hit before committing.
5. **The exit criteria, in order:**
   1. quote the toolchain's version. Refresh nothing: CI's run is the gate of
      record, and a local run is a pre-check (`.agents/rules/unattended.md`,
      "Claim only what you ran");
   2. run every command of `.agents/rules/verification.md`, "The gate", read
      from that file and **never copied here**, each with what it printed;
   3. run the guards below whose condition the change meets;
   4. re-read every line the change quotes or relies on, at the head, and
      quote the comparison;
   5. push;
   6. read CI on the head (`.agents/rules/verification.md`, "Which run
      covers a commit"), the latest run per check:
      - red: fix and push again, up to the bound on CI-fix attempts per fire;
      - cancelled: read it again, and never count it as red;
      - no run on the head: neither pass nor fail. Say so in the progress
        checklist.
6. **Progress**, in one body write: the progress line, its `slice=` the
   number of the plan step this slice finished, and the checklist above the
   block.

   ```
   ## Progress
   - [x] 1. <plan step> — <commit>
   - [ ] 2. <plan step>
   - [x] M-<n> — <commit>
   CI-fix attempts this fire: <n>
   ```

   Each item of the worklist before the trio has one `M-<n>` line, ticked
   with its commit in the slice that finishes it and never earlier.

7. **End a non-final slice.** A `slices_day` that is not today counts as 0
   before the increment.
   1. Raise `slices` by one and set `slices_day` to today, in the same write.
   2. Release the claim.
   3. Then check the daily cap. Below it: re-enter `spec/approved`. At it:
      pause for the day, leave the label, and say where the next fire
      resumes.

   A fire that dies between the release and the re-entry is recovered by the
   clerk's reconstruction.

**The guards a change's content triggers**, each from a recorded rule:

- A change to a dependency keeps `THIRD-PARTY-NOTICES.md` and the licence
  section of `README.md` current in the same change (`AGENTS.md`, "License
  compliance is part of every change").
- A change to user-visible behaviour, setup, privacy or the release workflow
  updates the docs in the same change (`AGENTS.md`, "Before you open a pull
  request").
- A change to the spelling and grammar hints or to input-source reading runs
  the tests gated off CI (`.agents/rules/verification.md`, "What a green run
  does not prove"), and quotes their counts.
- A change to the speech-recognition engine needs a recognition-quality
  review on real hardware (`AGENTS.md`, "Non-negotiable principles", 4 and
  6). No run here can give it, so it goes under "Only a live run can prove".
- Moving the pinned changelog tool needs the replay in `docs/release-ci.md`,
  "Version computation".

## The final slice

Exactly in this order:

1. Implement and verify to the exit criteria.
2. Record the commit before deletion as `predelete=` on the progress line,
   and read it back. It keeps the specification readable later, and is the
   permalink target. Where the directory is already absent at the head, keep
   the recorded value. With no value recorded, use the parent of the newest
   commit that deleted the directory, and say so in the report.
3. Delete the specification directory entirely.
4. Commit and push. Then rerun the exit criteria on this head.
5. Confirm through the code host that the head equals the local commit. Then
   record the tree id.
6. Run the two checks the clerk's round will make, and quote both outputs:
   - no file in the specification directory is tracked at the head. A file
     still tracked: delete it and go back to step 4;
   - the diff against `main` is not empty. An empty diff is the stop
     condition of a return of kind 3.
7. Build the worklist before the trio ("The acceptance trio"). Only once it
   is empty, dispatch the trio over the pushed diff. **The item's last push
   came before it.**
8. Take the last read (the law, "Narrowing, restore and the last read").
   Then the exit writes: the verdict comment, the completion line, and on an
   accepted verdict only, the hand-off.

The trio judges the pushed tree, the same tree the owner and the round will
see. Judging before deletion would accept a tree that no longer exists by the
time anything acts.

## The acceptance trio

Three sub-agents in the seats of `.agents/rules/process.md`, "The three
seats", under `.agents/rules/evidence.md`. Three is the round's ceiling. They
get `$RUN/diff.patch` and a case file rebuilt this fire from durable records,
holding:

- the pull-request body;
- the narrowed sources that count, each with its close reason;
- the earlier findings: every `M-n` (the law, "Findings"), each with its
  `Check:` and the result its verdict quoted, except those your settlement
  comments record and those about a narrowed source's work. A restore brings
  the latter back;
- the commands you ran and their outputs;
- the specification, read at `predelete=`.

Paths, never text. No reasoning, confidence or hint of yours. The trio does
not judge a narrowed source's work: its outcome is already decided. These
files carry third-party text, so every brief says in its own words what
`.agents/rules/unattended.md`, "Instructions and evidence", requires of it.

**The worklist before the trio.** First record each settlement: for an
`M-n` an owner's review comment names, and no comment of yours records yet,
post one comment `M-<n>: settled by the owner's review comment <link>.`,
ending with its key line. Then build the worklist: every earlier `M-n` whose
check fails at the head, except those your settlement comments record, each
with its check and the result observed, and the worklist of every
`Narrowing:` or `Restored:` comment that counts and is not yet worked.
Dispatch the trio only when it is empty. Otherwise work it through the slice
loop. A list that does not fit one slice ends as a non-final slice does
("The slice loop", step 7). An `M-n` on the worklist, ticked in the progress
checklist, whose check still gives the result its verdict quoted has
returned (the law,
"Findings"): post the stop comment of the rejected path's step 2, write its
stop line in one body write, leave `spec/approved`, and end.

- **Prosecutor**: may compile, test and write reproductions under `$RUN`,
  each a program of its own, never code the case file carries. It runs the
  check of every earlier finding and quotes the output, as part of what it
  attempted.
- **Judge**: reads the diff, the specification, the narrowed sources, the
  earlier findings and both reports only, and returns exactly, one line per
  entry:

  ```
  VERDICT: ACCEPTED
  confidence: 1-5
  established: facts the record proves, each with its exhibit
  struck: assertions rejected for lack of evidence
  must_change: the worklist, if REJECTED; each item with its Check:, the result observed, and what would make the check pass
  returned: on a REJECTED only, each earlier M-n whose quoted output is the result its verdict quoted, citing that exhibit
  not_verified: what nothing in the record establishes
  ```

  The first line is `VERDICT: ACCEPTED` or `VERDICT: REJECTED` and carries
  nothing else. `returned:` on an `ACCEPTED` verdict is another shape. Ask
  again for any other shape, up to the bound on judge output shape. Then
  treat it as rejected.
- **Rejected**: no retitle and no body rewrite. A rejected item never wears a
  finished item's clothes.
  1. Post the verdict comment with `must_change` as the worklist, its last
     line the `REJECTED` verdict line at the tree id
     (`.agents/rules/markers.md`, "The verdict line").
  2. Where `returned:` names an item, post one stop comment naming each
     returned `M-n` with its check and the unchanged result, ending with the
     stop line (`kind=no-progress`, `key_kind=tree-id`).
  3. Write the `rejected` completion line, with the stop line where step 2
     posted one, in one body write.
  4. With a stop, leave `spec/approved` and end. Otherwise go on through the
     slice loop with the worklist before the trio.
- Never overrule the judge, never soften a rejection, and never hand off on
  anything but a quoted `VERDICT: ACCEPTED`. This binds your own judgement.
  An `M-n` the owner settled (the law, "Findings") leaves the earlier
  findings by the owner's ruling.

## The hand-off on an accepted verdict

No second push: another commit would change the tree under the verdict. The
last read comes first. Each step checks whether it already landed, and
repeats nothing that did.

1. **The verdict comment**: the judge's `established` list with its
   exhibits, and `not_verified` in full. Confidence and `struck` go in your
   report: they are the session's machinery, and this comment outlives the
   session. End it with the `ACCEPTED` verdict line at the tree id, and read
   it back.
2. **Retitle** from `Spec: …` to the conventional header the change will
   merge under (`AGENTS.md`, "Before you open a pull request"). The type
   follows the kind label of the item's sources, by the line below. Where
   sources map to different types, take the one that releases the higher
   version (`cliff.toml`): `feat:` over `fix:`, and either over `refactor:`
   and `docs:`, which release nothing. Between those two, take `refactor:`.
   Read the title back.

   Header type by kind: `bug` → `fix:`; `enhancement` → `feat:`;
   `tech-debt` → `refactor:`; `documentation` → `docs:`.
3. **One summary comment**, ending with its key line: what this fire did,
   which review comments it answered, each `M-n` worked since the previous
   `ACCEPTED` verdict with its commit, the verification, and a link to the
   verdict.
4. **Rewrite the pull-request body for the owner**, in one body write. Its
   state block carries the `accepted` completion line at the verdict's tree.
   That verdict closes every earlier `M-n`: a later case file's earlier
   findings start after it (the law, "Findings"). Keep the state block and
   the fingerprint. Drop the progress checklist. "Only a live run can prove"
   is never skipped: it is the owner's checklist for the dev build, built
   from `not_verified`.

   ```
   ## What was done, and why
   The root, in one paragraph.

   ## How, and why this way
   Only decisions a reader cannot recover from the diff: alternatives rejected and why.

   ## Verified
   The commands and their counts, one line each, and the Swift run on the head by number and conclusion, or `pending` where none has finished. The clerk's round reads the result.

   ## Only a live run can prove
   Each effect outside the process, one line each.

   ## Links
   - the specification as it stood: <permalink at the predelete commit>
   - narrowed: #<b> — <close reason>

   <the state block, every other line unchanged, then the item fingerprint>
   ```

   Read the body back, every line of the block.
5. **Finish the labels**: re-read labels and state, remove `spec/approved`,
   apply `pipeline/code-review`, and read the set back.

The completion line lands after the title and the summary. A fire that dies
before it is finished by a later fire from the verdict comment ("The
deterministic gate").

## Never

The law holds in full, its "What no stage writes" and "Bounds" among it.
Beyond it, never:

- edit the specification: a gate objection sends it to the writer;
- push after the trio ran;
- post an `ACCEPTED` verdict line for a tree the judge did not accept.

## The report

In the law's order ("Preconditions, read-back and reporting"). Your own
section: the slice worked, each exit criterion with its output, the trio's
verdict with its confidence and what it struck, and every test count in the
form `.agents/rules/unattended.md`, "Reporting", gives, the ignored tests
named.
