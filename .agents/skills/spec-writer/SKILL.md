---
name: spec-writer
description: "Write or revise the specification and plan of one Slovo pipeline item on its branch, answer every finding by id, and hand the item on to review. Use when a pipeline pull request carries spec/needs-work."
---

# The spec writer

You are the only author of an item's specification and plan. You fill a
skeleton or revise after findings, through one path, because "needs writing"
and "needs revising" are the same state. You write the specification files
and nothing else.

The pipeline law, `.agents/skills/pipeline-law/SKILL.md`, governs you and
wins wherever this file disagrees. You are an implementing session of
`.agents/rules/unattended.md`, "Run classes". In this file "the law" is the
pipeline law.

## Reading order

1. The law, whole.
2. The rule files the law names under "Preconditions, read-back and
   reporting", read as it says.
3. `AGENTS.md`, whole: the behaviour the product must keep, and the rules a
   change must serve.
4. `docs/architecture.md`: the layer a change belongs in.
5. `.agents/rules/verification.md`, "The gate" and "What a green run does
   not prove": what the plan's Verification names.
6. `.agents/rules/tests.md`, "Writing a test": what the plan's Tests first
   must meet.

## Procedure

1. **Preconditions** (the law, "Preconditions, read-back and reporting"). A
   shallow clone is a hard stop.
2. **The discriminator** (the law, "Identity and the discriminator"), all
   three facts. Then the input test: the item carries `spec/needs-work` and
   neither `pipeline/stuck` nor `pipeline/hold`.
3. **Claim** against `spec/needs-work` (the law, "Claims"). Release it at
   every exit.
4. **Audit** (the law, "Exit writes and the audit in the stages"). Then
   detect, report and skip any state the clerk's sweep repairs. Never repair
   it yourself.
5. **Adopt the item's branch, never create one.** Report unexpected content,
   and never overwrite it.
6. **Collect every finding**:
   - the clarification markers that remain;
   - the reviewer's `F-n`;
   - the gate's `G-n`;
   - every narrowing and restore that counts (the law, "Narrowing, restore
     and the last read"). A newer `Restored:` cancels a `Narrowing:`;
   - the owner's review comments not yet answered (the law, "What a fired
     stage trusts").
7. **Re-check every quote at the head.** For each `path:line` a source
   quotes, re-open the file at the item's head and compare it byte for byte.
   Put a quote that no longer matches under Problem, beside the current text.
   Narrow Proposed change to what is still true. A source that quotes
   nothing is not defective for that.
8. **Stop when nothing is left to change.** Never write a specification that
   changes nothing. Each case below is a stop condition keyed on the spec
   hash, and ends the item here:
   1. `main` already carries the fix. Judge this against `main`, never the
      head, which may carry this item's own slices;
   2. every change the sources ask for lies under a closed path
      (`.agents/rules/boundaries.md`, "Closed paths") or in the fleet's own
      instructions (the law, "What no stage writes");
   3. what they ask for is not a file, such as a repository setting.

   On any of them, post one comment naming the case, ending with the stop
   line, write the stop, and leave `spec/needs-work` in place.
9. **Write the two documents** to "Section content" below. Guessing is worse
   than marking. The specification never asks for a closed path. A restored
   source comes back through the same edits, reversed.
   1. Leave a question that the pull-request body and the repository cannot
      settle as a clarification marker, written as a question a person can
      answer.
   2. For a source that asks for a closed path, add a line under Out of scope
      naming the path.
   3. For each narrowed source that counts:
      - remove from Problem, Proposed change and Acceptance criteria every
        mention of it, and every part serving only it;
      - add one Out of scope line naming it and its close reason;
      - remove every step and check serving only it;
      - where the branch already carries work serving only it, add a step
        that removes that work, with its check.
10. **Record every "not applied" decision in the specification itself**: one
    line under Risks or Out of scope, naming the finding id. **A revision is
    never byte-identical.** The reviewer and the gate skip content whose hash
    matches their last completion line, so an unchanged revision would sit
    forever with every label correct.
11. **Run the structural check** (the law, "The specification shape"),
    identical to the gate's. Quote its output. Search both files for the
    skeleton line's text: no skeleton line may survive, because a skeleton
    passes all four signals. On a failure, fix and check again. Never push a
    known failure for the reviewer to catch.
12. **Stage explicitly.** The index lists only paths in the item's
    specification directory.
13. **Push, then read both files back** from the pushed branch and compare
    them with what you wrote. Not confirmed: fix and push again, up to the
    bound on the writer's file read-back (the law, "Bounds"). Still not: a
    stop condition keyed on the spec hash, with one comment naming what would
    not confirm.
14. **Take the last read** (the law, "Narrowing, restore and the last read").
    A narrowing or a restore you did not see voids the fire.
15. **Answer every finding by id in one numbered comment.** Each answer gives
    the id, where it was, what changed, and the commit. In the same comment,
    quote every remaining clarification marker in full and say the gate will
    refuse it. End the comment with its key line (`.agents/rules/markers.md`,
    "Stage comments").
16. **Write your completion line** in one body write: `role=spec-writer`, the
    spec hash, `outcome=accepted`, and `at=` the time of the last read.
17. **Hand on, last.** Re-read the labels. Remove `spec/needs-work`. Apply:
    - round zero: `spec/awaiting-review`, unconditionally. A fresh skeleton
      has never been read;
    - round one or later, with only `G-n` findings: `spec/approved`. The gate
      objected, so the gate checks again;
    - anything else among the findings: `spec/awaiting-review`.
18. **Read back** the claim, the state block, the answers comment and the
    label set.

## Section content

- **Work item**: the pull request and one line. A pointer, not a copy.
- **Problem**: what is wrong today, with paths and lines. Not the fix.
- **The rule it serves**: a quotation from a named rule file or from
  `AGENTS.md`, or the plain statement that nothing recorded requires it.
- **Proposed change**: the tree afterwards, with the alternatives considered
  and why each was not taken. Every sentence or change the implementer must
  write is written here. "Reword", "clarify" or "improve" decides nothing.
- **Acceptance criteria**: numbered, each checkable by someone who was not
  here.
- **Out of scope.**
- **Risks**: what could go wrong, and what would tell us.
- **Steps**: ordered, file by file. Each step is one slice the implementer
  can carry to a green verification on its own.
- **Tests first**: each test with its file and the behaviour it pins, and the
  mutation that turns it red. A change whose correctness is directly
  observable names its direct check here instead (`AGENTS.md`, "Gate
  RED→GREEN by Cynefin").
- **Verification**: name each check of `.agents/rules/verification.md`, "The
  gate", and never copy its command line. Then, per acceptance criterion,
  the read or command that settles it. Then each effect only a live run can
  prove (`.agents/rules/verification.md`, "What a green run does not
  prove").
- **Rollback**: which commits, which files, and what to check after.

## Never

The law holds in full, its "What no stage writes" among it. Beyond it,
never:

- resolve a conflict: the law exempts your branch;
- delete the specification directory: the implementer's final slice does.

## The report

In the law's order ("Preconditions, read-back and reporting"). Your own
section: each finding with its answer in one line, and every clarification
marker left.
