# Design vocabulary

The standard is "do not complicate the code", and cognitive load is the
measure (`AGENTS.md`, "Standing owner directives", 1). This file gives
reviewers words they can point at, and the places in this repository's tree
that already answer each question. The abstraction police and the
proportion police judge by it, and the court tries their findings by it.

## Name the symptom

An objection names one of these symptoms, or a plain term such as
"complexity that buys nothing" or "a general mechanism where a specific one
would do". An objection with no symptom is withdrawn.

- **Shallow module:** the interface is not much simpler than the
  implementation.
- **Pass-through method:** it forwards its arguments to a similar signature
  one layer down.
- **Information leakage:** one design decision is reflected in more than one
  module, so both change together.
- **Overexposure:** the interface makes a caller learn a rare case to reach a
  common one.

## Rules of judgement

- **Dispatch is not pass-through.** A closed set whose methods hand over to
  per-variant modules is the interface itself.
- **Shallow on purpose.** A module of constants with their reasoning beside
  them is a recalibration seam. Do not fold it into callers.
- **Interface ahead of its caller.** A package's own tests, examples and
  binaries do not keep its interface alive. Narrow visibility to the callers
  that exist, and say in one line who they are. A widened surface whose
  reason names a future caller is worth waiting on: the written reason is
  what ends the wait at the right moment.
- **Prefer the specific mechanism** until a second caller exists. Say what a
  general one buys before proposing it.
- **Errors defined out of existence.** A closed set read leniently and
  written in one spelling, with no other way in, cannot hold an invalid
  value. Prefer that to a check somewhere else.
- **The owner's directives are measured against too**: `AGENTS.md`,
  "Standing owner directives", 1, 4 and 5.

## Recorded answers in this tree

Shapes that read as ceremony or duplication to an outside eye, with the
reason that keeps each. A finding that lands on one engages its reason or is
not filed. Every number a finding states about them is re-measured at the
analysed commit.

- **The target split is the design.** `SlovoCore` stays free of the app
  shell, of launch-at-login and of the update engine, and the package's
  target graph enforces it: an import of the update engine in the core
  cannot compile. The reasons stand beside the dependencies and targets in
  `Package.swift`, and in `docs/architecture.md`, "Build Boundaries".
- **`SlovoObjC` is a one-purpose Objective-C bucket.** It wraps what Swift
  cannot express, an exception the audio framework raises, and it is exempt
  from the Swift settings and lint gates on purpose (`Package.swift`, the
  comment on the `SlovoObjC` target).
- **`SlovoTestSupport` exists for tests.** It is a separate library so the
  shipped executable never links the fakes (`Package.swift`, the comment on
  the target). A type there used only from tests is not dead.
- **One mutation path.** `AppStore.update` is the only way state changes,
  and effects are subscribers keyed on slices of the state
  (`docs/architecture.md`, "App State"). A second path to the same state is
  information leakage, never a convenience.
- **Reliability mechanisms `AGENTS.md` argues for.** The sound-cue FIFO and
  its release deadline, the per-dictation cue queue and the withhold
  boundary around the Start cue are recorded as earning their keep
  (`AGENTS.md`, "Product intent — how the app must work", "Sound cues").

This file describes shapes in the tree. Where the tree and this file
disagree, the tree wins and this file is stale.
