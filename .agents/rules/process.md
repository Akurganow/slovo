# Process: acceptance rounds and the cycle for implementing work

How implementing work is criticised, executed, prosecuted and accepted. The
pipeline's stages follow it, and so does a person who runs an acceptance
round. This file yields to `AGENTS.md`, "Engineering process", which holds
the owner's recorded decisions on how work is done here. How each exhibit is
proved is in `.agents/rules/evidence.md`.

## The three seats

- **Prosecutor.** Argues the work cannot be accepted. Its round is judged by
  what it read and tried, never by what it found. It shows:
  - what it read;
  - the whole change against every named rule file;
  - what it attempted.

  Finding nothing after that is a normal result, stated in one line. A
  prosecution that shows neither what it read nor what it tried has failed.
- **Advocate.** Argues the case for the work:
  - which objections are real defects;
  - which are style dressed as defects;
  - what the work demonstrably does that the prosecution passed over.

  It concedes what the evidence does not support. Without it a judge hears
  one side.
- **Judge.** Decides after reading both. It is the only seat that may say
  the goal is reached. It is never a fourth reviewer, an agent that took
  part in the work, or the orchestrating lead.

Every seat is a fresh agent every time. An agent that argued a position
never judges it later.

## Two conditions bind a verdict

- **No workarounds.** A green result reached by special-casing what failed
  does not pass. It is worse than red, because it spends the credibility of
  every later green.
- **The judge must have seen it.** The verdict rests on evidence a stranger
  could reach: run ids, job logs, rendered output. It never rests on the
  lead's assertion.

## The process cycle

1. **Clustering.** Gather decisions into clusters big enough to skip
   per-detail review and small enough for one critic to hold.
2. **Criticism of the decision before the code.** An independent critic
   takes the intent apart before anything is planned. A wrong idea
   implemented cleanly is still a defect.
3. **Execution.** Each executor works from its own file list. Two parallel
   executors never share a file. No executor reviews itself.
4. **Prosecution after the code, before the merge.** A separate agent gets
   the diff and the instruction to prove it cannot be merged, with
   executable oracles: tests, byte comparisons, live runs.
5. **A live run before the merge.** Checks run against the pull request's
   merge result. Anything with an effect outside the process is proved by a
   live run, not by tests. Here the live run is the owner's, on the dev
   build, before the owner merges (`AGENTS.md`, "Standing owner
   directives", 3).
6. **Acceptance.** A large round ends with the three seats, never with a
   single reviewer.

## What "done" means

The owner's merge marks work done (`AGENTS.md`, "Standing owner
directives", 3). What reaches it holds all of these at once:

- no defects: checks are green and a live run confirms the behaviour on real
  data. Every known hole is closed or written down as an accepted risk;
- nothing harmful: nothing distorts what a reader sees, publishes unchecked
  text, or corrupts data under a race;
- clean code: module boundaries mean something, invariants are written beside
  the code, no copy-paste, no "just for now";
- checked against practice: on a non-obvious question, research comes first
  and the decision second. A departure from the field's practice has its
  reason written down.

A commit message explains why, not a retelling of the diff. A decision that
shapes the code is written beside that code, or in the docs where a reader
needs it first. Never in a document whose only job is to hold decisions.
