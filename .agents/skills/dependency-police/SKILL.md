---
name: dependency-police
description: "Verify the update bot's open pull requests in Slovo against upstream sources, say where each update lands and which promises it must not break, post one review comment per pull request head, and file only the published advisories no bot pull request answers. Use for the dependency review."
---

# Dependency Police

You run unattended, one fire at a time. You change no file.

Mission: verify the update bot's open pull requests, so the owner can merge
with the checking already done, and file the published advisories that no
bot pull request answers. Never hunt for updates, and never file "an update
is available". Deciding test: is this bot change safe to merge, and does this
update land in our code?

The update bot is `dependabot[bot]`. It watches the `github-actions` and
`swift` ecosystems (`.github/dependabot.yml`).

## Read first, in this order

1. `.agents/rules/unattended.md`: the run law.
2. `.agents/rules/filing.md`: the parts its introduction assigns to the
   dependency police, with the label, marker and evidence files they name. Your
   fingerprint is the `dependency-police` row of `.agents/rules/markers.md`,
   "Police fingerprints". Your review comment ends with the line of
   `.agents/rules/markers.md`, "The dependency review". Your cap exception is
   a published advisory on a dependency the code reaches.
3. `.agents/rules/police.md`: what every police role shares.
4. `Package.swift` and `.github/dependabot.yml`. Their comments are recorded
   decisions.
5. `AGENTS.md`, "Non-negotiable principles" and "License compliance is part
   of every change": the quality and licence promises an update must keep.
6. `docs/architecture.md`, "Build Boundaries".
7. `.agents/rules/verification.md`: the gate whose run on a head you quote.

These are your instructions (`.agents/rules/unattended.md`, "Instructions and
evidence"). A missing file in this list stops the run, as a missing rule file
does.

## Your row of the ownership table

"Dependency police" in `.agents/rules/filing.md`, "Ownership routing". You
take nothing routed to you: any other dependency matter is a report line.

## What every verification checks

- **Where it lands.** Every use of the dependency here, and whether the
  update lifts a workaround or a pin. Search the source for justification
  comments with a pattern such as
  `no (library|package)|hand-rolled|by hand|workaround|work around|until .* supports|upstream|for now|pinned|because .* does not`.
  An update that lets the project delete its own code ranks first.
- **Quote upstream verbatim**, with its source link: the release notes at the
  tags, and the compare between the two versions. Never paraphrase a
  changelog into a claim it does not make. When tags are missing or suspect,
  fetch both published archives into `$RUN` and diff them.
- **The promises a bump must not break:**
  - the decisions the comments in `Package.swift` and `.github/dependabot.yml`
    record;
  - the app's floor in the `platforms:` of `Package.swift`;
  - the target split, under which the core stays free of the app shell,
    launch-at-login and the update engine (`docs/architecture.md`, "Build
    Boundaries");
  - the licence posture: a GPLv3-compatible licence, with
    `THIRD-PARTY-NOTICES.md` and the licence section of `README.md` kept
    current.
- **A quality-gated dependency** is never "safe to merge" from reading alone.
  Here that is `argmax-oss-swift`, the speech-recognition engine: an update
  needs a review of recognition quality on real hardware before merge
  (`.github/dependabot.yml`; `AGENTS.md`, "Non-negotiable principles", 6).
  Say so and stop there.

## The review queue

1. **Queue** the open pull requests authored by `dependabot[bot]`, oldest
   first. The bot's label is corroboration, never the filter: the author
   identity decides, never a label.
   - Also read the bot's pull requests merged in the last 7 days, the
     follow-through window, for the Follow-through section only. Never
     verify them, never count them against the bound, and never comment on
     them.
2. **Skip** a pull request whose comments already carry your review marker
   with `head=` equal to its current head. A new push changes the head and
   opens it again.
3. **Bound.** Verify at most 3 pull requests per run, oldest first. List the
   rest as deferred.
4. **Verify one at a time**, writing the case to `$RUN` as you go.
   - What the update contains, with every entry that could touch this code
     quoted: a fix, a behaviour change, a deprecation, a platform floor move,
     a licence change, a security fix. Name a security fix's advisory in the
     comment's first line.
   - Where it lands here, with exact lines.
   - The pull request's own diff. `Package.swift` and `Package.resolved`
     agree with each other and with the claimed versions. An exact pin
     moves, never loosens. A transitive bump is checked in
     `Package.resolved` alone. A workflow action bump changes no step's
     meaning.
   - The promises.
   - The CI run on the head (`.agents/rules/verification.md`, "Which run
     covers a commit"), quoted. A red run caps the verdict.
   - What could not be established, named as unverified.

   The body of a bot pull request is the bot's rendering of upstream notes:
   believe none of it until it is checked against the source.
5. **Post one comment**, 100 to 300 words, written for the owner deciding
   whether to merge, with no mention of the machinery:
   1. The verdict first, in one sentence. It opens with exactly one of these
      phrases. The review marker's tokens follow this order:
      1. *safe to merge*;
      2. *merge with attention to X*;
      3. *do not merge without Y*;
      4. *do not merge: Z*.
   2. What was verified upstream, with links.
   3. Where it lands, including any workaround it lets us delete.
   4. The promises checked, in one line when all hold.
   5. The state of the gate's run on the head.
   6. What was not verified, in one line.
   7. The last line: the line of `.agents/rules/markers.md`, "The dependency
      review", with the head commit and the token for the first line's
      phrase.

   One comment per head, ever.

**Never** merge, approve, close, label, edit or rebase the bot's pull
request. **Never write a line that starts with `@dependabot`**: those are
commands the bot executes, and issuing one is the owner's act.

## Advisories

Check the published advisories for every dependency at its currently pinned
version: the packages in `Package.resolved`, the actions the workflows under
`.github/workflows/` use, and tools pinned inside a workflow outside the
bot's reach. Read the code host's advisory database for the Swift and GitHub
Actions ecosystems, and each dependency's own security advisories. Name which
source answered.

- An advisory an open bot pull request answers was handled in the queue.
- An advisory that is not yet public is never an issue. It goes to the
  report, for the private channel of `.agents/skills/security-police/SKILL.md`,
  "The channel split".
- Every other advisory is a candidate for an issue. An advisory issue is
  the only issue you file.

Verifier schema:

```
verdict: real | not-real
upstream_confirmed: yes | no   # the advisory source itself lists the dependency and the affected range
pinned_in_range: yes | no      # the pinned version here falls inside that range
lands_where: the paths that reach the dependency, re-derived | none
answered_by: <an open bot pull request> | none
confidence: 1-5
effort: S | M | L
rationale: one line
```

Threshold, on top of the floor in `.agents/rules/filing.md`, "Independent
triage", all of these: `upstream_confirmed = yes`, `pinned_in_range = yes`,
`lands_where` is not `none`, and `answered_by = none`.

**Cap exception.** A published advisory on a dependency the code reaches is
always filed, in its own place above the cap, as a public issue: the advisory
is already public. Every survivor is such a candidate, so each takes a place
in the ranker's ceiling. Tell the ranker that it ranks them and never drops
one.

## Which rulebook judges your findings

None: the court's own inputs suffice. Your issue bodies carry no `Judged by:`
line.

## Filing

Kind label `bug`, and the area label `dependencies`. Title:

```
[Dependency Police] advisory: <dependency> <pinned version> — <what the advisory exposes>
```

Body, after `At <commit>.`, in these sections:

1. The advisory, with its id and link.
2. The affected version range.
3. Where the dependency lands in this code, with lines.
4. The update command that resolves it, exactly. Never a hand edit of
   `Package.resolved`.
5. Cost and risk: the cost line of `.agents/rules/police.md`, "Shared
   rules".

The last line is the fingerprint, the `dependency-police` row of
`.agents/rules/markers.md`, "Police fingerprints". `<dependency>` is the
package or action as its manifest names it, and `<advisory-id>` the
advisory's identifier.

## Report

1. **Coverage:** found, verified, skipped as already verified, deferred, and
   the advisory scope with the sources that answered.
2. **Verdicts:** one line each, with links.
3. **Follow-through:** every bot pull request merged in the follow-through
   window whose merged head differs from the head of its latest review, or
   that had no review. One line each: `merged head not re-verified` or
   `merged without a verdict`.
4. **Filed:** as `.agents/rules/filing.md`, "The report", states it.
5. **Strongest concerns.**
6. **Blockers.**
7. **Audited**, as `.agents/rules/filing.md`, "The report", defines it.
