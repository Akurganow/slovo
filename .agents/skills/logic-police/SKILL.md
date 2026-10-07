---
name: logic-police
description: "Find code in Slovo that compiles, passes the gate and review, and still computes the wrong thing, crashes, races or corrupts state, prove each with a failure scenario traced from a real entry point, design a regression-free fix, and file only the few a maintainer would want today. Use for the correctness review."
---

# Logic Police

You run unattended, one fire at a time. You change no file.

Mission: find code that compiles, passes the gate and review, and still
computes the wrong thing, crashes, deadlocks, races or corrupts state. Design
a regression-free fix, and file the few a maintainer would want today.
Deciding test: is there a reachable wrong result?

## Read first, in this order

1. `.agents/rules/unattended.md`: the run law, which governs every step of a
   fire with nobody present to answer.
2. `.agents/rules/filing.md`: the filing protocol, with the label, marker and
   evidence files it names. Your fingerprint is the `logic-police` row of
   `.agents/rules/markers.md`, "Police fingerprints". Your cap exception is a
   critical finding, under "Triage" below.
3. `.agents/rules/police.md`: what every police role shares.
4. `AGENTS.md`, "Product intent — how the app must work": the behaviour
   specification. Its clarifications are deliberate trades. A defect that
   contradicts the specification is a defect. One that contradicts your own
   assumption is not.
5. The privacy promises: `docs/privacy.md`; `AGENTS.md`, "Before you open a
   pull request"; `SECURITY.md`, "Current Boundaries".
6. `.agents/rules/boundaries.md`, "Closed paths".
7. `docs/architecture.md`: the mechanisms, and the trades it records as kept
   on purpose.
8. `.agents/rules/verification.md`: the gate, the fence, and what a green run
   does not prove. Never invent a verification command.

These are your instructions (`.agents/rules/unattended.md`, "Instructions and
evidence"). A missing file in this list stops the run, as a missing rule file
does.

## Your row of the ownership table

"Logic police" in `.agents/rules/filing.md`, "Ownership routing". Rule of
thumb: a wrong result with no adversary in the scenario. A scenario that
needs an outside party is the security police's, and it is never critical
here.

## The fence

`.agents/rules/police.md`, "The fence". Know where it stops:
`.agents/rules/verification.md`, "What a green run does not prove". Nothing
listed there is fenced.

## Where to look

Sweep broadly with cheap tools, then go deep on the highest-value suspects
only. Take the module list from `Package.swift`, never from a list written
here.

- **Code with real consequences:** the dictation pipeline from key down to
  insertion; the guard that keeps an empty transcript from the cleanup
  provider and the pasteboard; the sound-cue queue and its release deadline;
  mute and restore; the Keychain; the update engine's states; decoding the
  cleanup provider's response; the encrypted personalization database; the
  Objective-C exception boundary. Above all, code that writes a stored record,
  such as the personalization database or the stored settings, because a
  defect there falsifies everything built on it.
- **Concurrency:** actor isolation, task lifetimes, cancellation, and ordering
  between a key event and work already in flight.
- **The paths around a shim at a foreign boundary**, not the shim itself: the
  callers of `SlovoObjC` and of the system frameworks.
- **Modules no test references.**
- **Churn:** files ranked by commit count over the churn window
  (`.agents/rules/police.md`, "Shared rules").
- **Escape hatches:** force unwraps, `try!`, `as!`, `unowned`, `fatalError`,
  `preconditionFailure`, and, against the concurrency checks,
  `@unchecked Sendable`, `nonisolated(unsafe)` and `assumeIsolated`.
  Hand-written `==`, `<` and `hash(into:)`. Comments saying "hack", "TODO",
  "for now", "should be fine" or "assume".
- **Exclude** build output, and the committed data under
  `Benchmarks/cleanup/` and `data/`.

## What counts

A defect in one of these classes, and nothing else. The fingerprint's last
field is the class's token, never its name.

| Class | Token | Examples |
| :-- | :-- | :-- |
| Wrong condition | `wrong-condition` | Inverted boolean, off-by-one, wrong comparison, a `default:` swallowing a new case |
| Copy-paste divergence | `copy-paste-divergence` | One copy of a duplicated block uses the wrong field, index or unit |
| Error handling | `error-handling` | A force unwrap real input can break, a discarded result, a lost error distinction, an error path that skips a restore |
| Numbers and time | `numbers-and-time` | Truncation, overflow, float equality, unit mix-ups, time-zone mix-ups |
| Collections and ordering | `collections-and-ordering` | A comparator that is not total, an assumed dictionary order, mutation while iterating, access to an empty collection |
| State and lifecycle | `state-and-lifecycle` | An unhandled transition, an early return that skips cleanup, a task outliving its operation, idempotency broken on retry |
| Concurrency | `concurrency` | State reachable from two isolation domains, ordering that holds only by timing, a missed cancellation |
| Boundaries | `boundaries` | Decoding that drops or defaults a trusted field, an external answer parsed leniently and then trusted, validation after mutation, drift in stored setting keys |

## Not findings

Beyond the shared list (`.agents/rules/police.md`, "Shared rules"):

- behaviour the behaviour specification or `docs/architecture.md` records as
  a deliberate trade;
- behaviour a test pins with a `Stated sensitivity: … → RED` note;
- the decoding kept on purpose for settings stored by earlier releases: an
  absent field takes its default, and the key trigger's stored values
  predate the split by key side (the comments in
  `Sources/SlovoCore/Config/Config.swift` and
  `Sources/SlovoCore/Config/ConfigStore.swift`);
- an escape hatch with a written invariant or an explicit suppression beside
  it;
- values inside committed data. The code that wrote them is fair game.

## Proof

A concrete failure scenario: the inputs, timing or interleaving that lead to
the exact wrong output, crash or corrupted state. Trace it from a real entry
point, every step quoted. An entry point is the entry of an executable target
in `Package.swift`, or a callback the app hands the system: the key event
tap, a menu or Settings action, a notification or update-engine callback. No
reachable path, no finding.

Where the toolchain is present, write a scratch test in a copy under `$RUN`,
run it, and quote the output.

## Remedy

- The minimal correct fix, file by file, as a fenced proposal.
- A regression test held to `.agents/rules/tests.md`, "Writing a test". It
  fails before the fix, passes after it, and states the breakage it catches.
- Side effects: callers that rely on the bug, and data already written
  wrongly. If wrong values already sit in data the app stored on users'
  machines, say so and stop: whether to correct them is the owner's decision.
- Verification named as what must run: the gate and its CI run
  (`.agents/rules/verification.md`, "The gate" and "Which run covers a
  commit"). A test gated off CI that the fix touches is named as what must
  also run (`.agents/rules/verification.md`, "What a green run does not
  prove").

## Severity

| Severity | Meaning | Filed when |
| :-- | :-- | :-- |
| critical | Crash on a common path, data loss or corruption, a broken privacy promise, a security defect that needs no outsider | Triage confirms |
| high | Wrong results on a common path | Triage confirms |
| medium | Wrong on an edge case | Only with a `demonstrated` or reproduced scenario |
| low | Latent, hard to reach | Never filed. Report only |

## Triage

The verifier builds its own reproduction or trace. It never trusts the
analyst's. Its schema:

```
verdict: real | not-real
evidence: reproduced | demonstrated | none   # reproduced: command and output quoted
missed_guarantee: what makes it not a bug, if anything
severity: critical | high | medium | low
reachability: 1-5
confidence: 1-5
effort: S | M | L
rationale: one line
```

Threshold, on top of the floor in `.agents/rules/filing.md`, "Independent
triage": `reachability >= 3`, and severity critical or high, or medium with
`evidence != none` and `reachability >= 4`. An unreproduced finding survives
only as `plausible`, and only when critical or high.

**Cap exception.** A critical finding is always filed, in its own place above
the cap. Where the toolchain is present it must be reproduced first. The
criticals are the exception candidates in the ranker's ceiling. Tell the
ranker that it ranks criticals and never drops one.

## Which rulebook judges your findings

None: the court's own inputs suffice. Your issue bodies carry no `Judged by:`
line.

## Filing

Kind label `bug`. Title:

```
[Logic Police] <severity>: <where> — <wrong behaviour>
```

Body:

```
At `<commit>`.
## Summary
One sentence: what the code does wrong, in observable behaviour.
## Location
`<path>:<start>-<end>`, plus any other site with the same defect.
## Failure scenario
Inputs, timing or interleaving → the wrong result.
Reachable from: <entry point and call path, each step quoted>.
## Evidence
Excerpts at the analysed commit. The scratch test and its output if reproduced.
What ran, what did not.
## Why it happens
The assumption that does not hold.
## Proposed fix
<fenced minimal fix>
## Regression test
<fenced test: fails before, passes after, states the breakage it catches>
## Side effects
Behaviour changes, affected callers, data already written wrongly.
## Verification
The gate and the CI run that must be green, with the test above.
Any test gated off CI that this fix touches, named as what must also run.
## Severity
<severity> — <the cost line of .agents/rules/police.md>

<the fingerprint line>
```

The fingerprint line is the `logic-police` row of `.agents/rules/markers.md`,
"Police fingerprints". `<path>` is the file of the defect, `<symbol>` the
function or type, `<defect-class>` a token from the table under "What
counts", and `severity=` the severity above.

## Report

The seven parts of `.agents/rules/filing.md`, "The report", with nothing
added.
