# Markers: the machine's state between runs

Every marker a role here writes or reads: its line, its writer and its
readers. Markers are the only state the fleet keeps between fires, so a
marker's line shape lives here and nowhere else. A role file or the pipeline
law cites the marker by its heading here and restates no line. When a marker
counts at all, placed on a line of its own and written by a trusted author,
is `.agents/rules/unattended.md`, "Instructions and evidence". The newest
trusted marker of one writer on one subject wins. Nobody edits an older one.

## Fields

- A field is `key=value`, or a positional field in a fingerprint.
- **Every value is a token.** No value contains a space or `::`. A value
  that would hold spaces is written with a hyphen for each space.
- `<sha>` and `<commit>` are full commit ids. `<12 hex>` is the first
  12 hexadecimal characters of the id or hash the field names. `<UTC>` is an
  ISO-8601 timestamp in UTC. `#<n>` names an issue and `#<cr>` a pull
  request.

## Police fingerprints

The last line of every issue a police role files, of that role's stale note
on its own issue, and of every draft private security advisory the security
police opens:

```
<!-- <role-id>-fingerprint: <field>::<field>::<class>[ severity=<critical|high|medium|low>] -->
```

- Every prefix ends in `-fingerprint:`, so one search for that string finds
  every automated issue.
- There are two or more positional fields. The last is the filer's class: a
  token from the closed vocabulary its role file defines.
- `severity=` follows the last field after one space, only from a role that
  grades severity. It is no part of the identity: fingerprints are compared
  without it. The court orders its queue by it.
- How a fingerprint is compared, and which fields are volatile, is
  `.agents/rules/filing.md`, "Identity: the fingerprint".

| Role id | Fields | `severity=` |
| :-- | :-- | :-- |
| `logic-police` | `<path>::<symbol>::<defect-class>` | Always |
| `abstraction-police` | `<path>::<symbol>::<kind>` | Never |
| `proportion-police` | `<path>::<symbol>::<kind>` | Never |
| `security-police` | `<surface>::<path>::<defect-class>` | Always |
| `dependency-police` | `<dependency>::<advisory-id>::advisory` | Never |
| `text-residue-police` | `<path>::<symbol-or-concept>::<kind>` | Never |
| `test-police` | `<path>::<test-or-cluster>::<kind>` | Never |
| `agent-police` | `<path>::<subject>::<kind>` | Never |

- **Writer:** the role the prefix names.
- **Readers:** every police role, for its do-not-report list, its cap, its
  stale note and its regression rule. The court, for its queue and for the
  filer's rulebook. The tracker clerk, to tell a police report.

## The court's marker

The last line of the court's one comment on an issue:

```
<!-- issue-court: sha=<trial commit> verdict=<verdict>[ duplicate_of=#<n>] -->
```

- `verdict` is one of `sustained`, `partially-sustained`, `not-proven`,
  `dismissed`, `out-of-scope`, `duplicate`, or `skipped` on the court's skip
  path.
- `duplicate_of` stands only beside `verdict=duplicate`, and names the
  survivor.
- **Writer:** the court.
- **Readers:** the court, for its queue and its audit. The tracker clerk, for
  the verdict it executes. The pipeline clerk at intake, for the marker's
  time only.

## The tracker clerk's marker

On a comment of the tracker clerk's: the closing comment of an issue it
closes, or a comment of its own on an issue that stays open.

```
<!-- slovo-clerk: sha=<court marker's sha|none> tip=<commit> action=<action>[ cr=#<cr>] -->
```

- `sha` is the court marker the action rests on, or `none` where no court
  marker stands. `tip` is the commit the fire re-derived at.
- `action` is one of:

  | Action | Closes the issue? | Extra field |
  | :-- | :-- | :-- |
  | `gone` | Yes, as completed | `cr=` when a merged pull request carried it |
  | `duplicate` | A police report, as a duplicate | |
  | `acquitted` | A police report, as not planned | |
  | `unmerged` | A police report, as not planned | `cr=` |
  | `handed` | No | |
  | `remainder-noted` | No | `cr=` |

- **Writer:** the tracker clerk.
- **Readers:** the tracker clerk, for its skip test and for a close marker on
  an open issue. The pipeline clerk at intake, for `action=handed`. Every
  police role, for `action=gone` under the regression rule of
  `.agents/rules/filing.md`.

## The taken marker

The last line of the pipeline clerk's comment on each source an item names,
written after the item opens and never rewritten:

```
<!-- pipeline-taken: item=#<cr> at=<UTC> -->
```

- **Writer:** the pipeline clerk.
- **Readers:** the tracker clerk, to bar a second hand-off. It is advisory:
  no close reads it, because a fire can die between opening the item and
  writing it. The item fingerprint is the authority.

## The dependency review

The last line of the dependency police's one comment on an update bot's pull
request, one per head:

```
<!-- dependency-review: head=<head commit> verdict=<safe|attention|condition|reject> -->
```

- Each token stands for the opening phrase of the comment, in the order the
  dependency police's role file lists the phrases. A phrase never stands in
  the marker, because its spaces and punctuation break the `key=value`
  reading.
- **Writer and reader:** the dependency police, by `head=`.

## The item fingerprint

The last line of every pipeline item's body. It closes the state block, and
it is never removed and never rewritten:

```
<!-- pipeline-work-fingerprint: <slug> sources=#<a>,#<b> -->
```

- `sources=` is the one link from an item to the issues it answers.
- A pull request counts as an item only when it also passes the
  discriminator in the pipeline law, "Identity and the discriminator".
- **Writer:** the pipeline clerk, when it opens the item. Every later body
  write keeps it.
- **Readers:** every pipeline role. The tracker clerk, for the closes after
  an item settles. Every police role, for its backpressure count and its
  regression rule.

## The state block

The mutable records of a pipeline item, at the foot of its body, directly
above the item fingerprint. The block is rewritten whole and read back line
by line:

```
<!-- pipeline-state: item=#<cr> review_rounds=<n> gate_bounces=<m> judge_rejects=<k> slices=<s> ci_waits=<w> ci_wait_head=<sha|none> cr_rounds=<c> narrowed=<#b,#c|none> -->
<!-- pipeline-claim: role=<role> item=#<cr> state=held|released at=<UTC> -->
<!-- pipeline-progress: item=#<cr> slice=<n> slices_day=<YYYY-MM-DD> predelete=<sha|none> -->
<!-- pipeline-stop: item=#<cr> kind=bound|condition key_kind=spec-hash|tree-id|head-sha key=<12 hex> spent_at=<UTC|none> at=<UTC> -->
<!-- pipeline-done: role=<role> item=#<cr> hash=<12 hex> outcome=accepted|rejected at=<UTC> -->
```

- One claim line per working role, and one completion line per role that
  writes one. The stop line is the newest stop.
- `<role>` is exactly one of `spec-writer`, `spec-reviewer`, `gate`,
  `implementer`. A token spelled any other way is a marker nobody can find.
- `cr_rounds` counts requests to the outside reviewer. Its seed and its
  bound are the pipeline law's, "Bounds".
- Once the clerk first asks the outside reviewer, the block also holds the
  clerk's `pipeline-cr` line ("The pipeline clerk's records").
- A stop is also the last line of the stop comment, in the same line shape.
- **Writers:** the pipeline roles, one writer per counter and per line, as
  the pipeline law, "Where state lives", assigns them. The pipeline clerk
  seeds the block when it opens the item.
- **Readers:** every pipeline role.

## Stage comments

The last line of every stage comment except a stop comment, which ends with
its stop line instead:

```
<!-- pipeline-comment: role=<role> kind=<findings|objections|answers|approval|summary|note> key=<12 hex> at=<UTC> -->
```

- `key` is the key that role's completion line uses.
- **Writer:** each pipeline stage, on its own comments.
- **Readers:** the stage's own audit. The pipeline clerk.

## The verdict line

The last line of the implementer's verdict comment, in place of the comment
key, for either outcome:

```
<!-- verdict: ACCEPTED|REJECTED tree=<12 hex> -->
```

- Every reader matches the outcome token, `ACCEPTED` or `REJECTED`, never
  the `verdict:` prefix alone.
- **Writer:** the implementer.
- **Readers:** the pipeline clerk's code-review round. The implementer's
  audit.

## The pipeline clerk's records

```
<!-- pipeline-stale: sources=#<a>,#<b> at=<UTC> -->
<!-- pipeline-carried: item=#<cr> verdict_tree=<12 hex> merge=<sha> at=<UTC> -->
<!-- pipeline-cr: head=<12 hex> outcome=asking|asked|returned|clean findings=<n> at=<UTC> -->
```

- `pipeline-stale` is the last line of the comment on an item closed because
  every source closed. `pipeline-carried` is the last line of the comment on
  one conflict merge the pipeline clerk made into an item whose
  implementation was already accepted: one comment per merge, never
  rewritten.
- `pipeline-cr` is the outside review's state: a line of the state block,
  rewritten with the block. `head=` names the head the request asked about,
  `outcome=` the step the clerk's round reached, and `findings=` the count
  of actionable findings in the answer, 0 until one returns.
- Comment openers, each the comment's first line exactly, one source or
  blocker per comment:
  - `Narrowing: #<n> closed as <reason>`, where `<reason>` is the close
    reason the code host records;
  - `Narrowing: blocker #<cr> closed unmerged`;
  - `Restored: #<n> reopened`.
- A body line above the state block: `Blocked by #<cr>`.
- **Writer:** the pipeline clerk.
- **Readers:** the pipeline clerk. The `Narrowing:`, `Restored:` and
  `Blocked by` lines are also read by the spec writer and the implementer at
  their last read, and by the spec reviewer.
