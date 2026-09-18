# Issues: filing and labelling

How an issue is filed and labelled here, for anyone who files one — a
person or an automated run (`tracker.md` adds the discipline for the
latter). Labels are the owner's: apply names already on the
repository's list and never create one; a name you need that is
missing is a line in your report, not a create.

## Labels

Four axes; the open list is read by them.

**Kind** — what the issue is. One per issue, set by whoever files it
(the issue templates set `bug` and `enhancement`).

| Label | Meaning |
| :-- | :-- |
| `bug` | Misbehaviour |
| `enhancement` | New behaviour |
| `tech-debt` | Code that works but costs more to keep than it should |
| `documentation` | The docs |

**Area** — where it sits, when it sits squarely in one. Any number.

| Label | Meaning |
| :-- | :-- |
| `asr` | Speech recognition |
| `cleanup` | The product's LLM cleanup step — prompts, model selection, output quality. **Never debt**: debt is `tech-debt`. |
| `i18n` | Language detection, multilingual support |
| `ux` | Interface behaviour |
| `dependencies`, `github_actions`, `swift_package_manager` | The update bot's pull requests; `dependencies` also marks a security-advisory issue |

**Provenance** — `police-report`: filed by an automated review run;
the fingerprint comment at the foot of the body names which one
(`tracker.md`).

**State** — how far the issue has been taken. At most one on an open
issue, set by whoever reviews it.

| Label | Meaning |
| :-- | :-- |
| *(none)* | Not yet reviewed |
| `question` | Further information is requested: from the reporter on a person's report; on an automated report, a decision from the owner, since the run cannot answer |
| `ready` | Specified to the standard below — a person can start the work from the issue alone |
| `invalid` | Reviewed and found wrong |
| `duplicate` | Duplicate of the issue the review names |
| `wontfix` | Out of scope. Applied by the owner it is final: an automated run never touches such an issue |

The owner's own: `good first issue`, `help wanted`; `dev-build` is a
pull-request button (`docs/release-ci.md`). An automated run never
applies them.

## Reading the open list

- `ready` — work a person can start.
- `question` — a person must answer.
- `invalid`, `duplicate` or `wontfix` on a person's issue — reviewed;
  closing is the owner's call.
- `police-report` with no state label — awaiting review.
- no state label and no `police-report` — a person's report awaiting
  review, or one already converted: a review comment on it names the
  `ready` issue that carries the work.

## The `ready` standard

An issue is `ready` when the owner can start the work from it without
opening the sources:

- title: imperative, the work itself, no prefixes;
- **Requirement** — what must be true when the work is done, in the
  product's terms, consistent with AGENTS.md;
- **Background** — the finding, and what a review established, struck
  or warned about;
- **Evidence** — the decisive code references as permalinks at a named
  commit;
- **Acceptance criteria** — checkable statements, each testable on a
  Mac;
- **Verification** — what must run and pass: the pull request's Swift
  check, which is `Scripts/diagnose.sh` in full on a macOS runner, plus
  any regression test proposed. Written where nothing was built, it says
  so;
- **Sources** — the issue it was cut from and the review it rests on.

A `ready` issue is a work item, never a report: it carries no
`police-report`.
