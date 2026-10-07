# Labels: the axes and what each label means

Every label a role applies or reads, by axis. Labels belong to the owner. A
run applies names already on the repository's label list and never creates
one. A name a run needs and cannot find follows
`.agents/rules/unattended.md`, "What a run needs from the code host".

## Axes

| Axis | Rule | Names |
| :-- | :-- | :-- |
| Kind | Exactly one per issue, set by whoever files it. The issue templates set `bug` and `enhancement` | `bug` (misbehaviour), `enhancement` (new behaviour), `tech-debt` (works, but costs more to keep than it should), `documentation` (the docs) |
| Area | Any number, only when the issue sits squarely in one | `asr` (speech recognition), `cleanup` (the product's text cleanup step: prompts, model selection, output quality), `i18n` (language detection, multilingual support), `ux` (interface behaviour). The update bot's own labels: `dependencies`, `github_actions`, `swift_package_manager`. `dependencies` also marks an advisory issue |
| Provenance | One label on every police issue. It decides membership of the machine population (`.agents/rules/filing.md`), so no issue template may apply it | `police-report` |
| State | At most one on an open issue, set by whoever reviews it | none, `question`, `ready`, `invalid`, `duplicate`, `wontfix` |
| Control | Applied by the owner, read by roles | `no-trial`: the court never tries the issue |
| Pipeline | On pull requests only. Each decides a stage or membership. Their meanings, who applies each and who removes it are the pipeline law's (`.agents/skills/pipeline-law/SKILL.md`, "Labels") | `pipeline/queued`, `spec/needs-work`, `spec/awaiting-review`, `spec/approved`, `pipeline/code-review`, `ready-for-human`, `pipeline/stuck`, `pipeline/hold` |

## State meanings

| State | Meaning |
| :-- | :-- |
| none | Not yet reviewed, or reviewed under a verdict that applies none. The review comment says which |
| `question` | A decision is needed from the owner, which the court's comment names |
| `ready` | Specified so a person can start the work from the issue alone. No role applies or removes it |
| `invalid` | Reviewed and found wrong |
| `duplicate` | Duplicate of the issue the review names |
| `wontfix` | Out of scope. **Applied only by the owner, and final.** No automated run touches such an issue |

## Owner-only labels

A run never applies `good first issue`, `help wanted`, or the build-trigger
label `dev-build`.

**One label, one meaning.** The court applies no label for out of scope:
its marker carries the verdict, and `wontfix` stays the owner's. The tracker
clerk skips every vetoed issue, so an out-of-scope report under the veto
label would never close.

## Reading the open list

- `police-report` and no state label: one of these, which the newest tracker
  clerk marker and any item naming the issue in `sources=` tell apart:
  - awaiting trial;
  - tried and awaiting the tracker clerk's close;
  - handed and awaiting the pipeline's intake;
  - carried by a pipeline item;
  - left open after a merge.
- `question`: the owner must answer.
- `invalid` or `duplicate`: reviewed. The tracker clerk closes a police
  report under its verdict.
- `wontfix`: the owner's veto, final.
- No `police-report`: a person's issue. No role reads it, and it waits for a
  person.

This file describes the labels the owner keeps on the repository. Where the
repository's label list disagrees with it, the list is what the code host
applies and this file is stale.
