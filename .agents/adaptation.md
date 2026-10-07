# Adaptation record

How this repository fills the slots of the fleet's build specification, what
the code host was measured to support, and where a fact of this repository
forced a value other than the specification's default. The agent police
reads this file like any other fleet document. Where a value lives in a rule
file, a role file or the pipeline law, this record names that place and does
not restate the value: the place is the authority.

## The owner's decisions

- **The delivery pipeline is built.** Sustained findings go to the pipeline
  clerk and the pipeline's stages.
- **Tracker scope is `machine`.** The repository is public, and no role
  reads an issue outside the machine population (`.agents/rules/filing.md`,
  "The machine population").
- **A gone finding closes as completed.** The tracker clerk closes a report
  once every claim re-derives as gone at the tip, tried or not.
- **The published-surface police and the record police are off.** The
  repository has no recurring operation that publishes a record. The rule
  files those roles would read are built all the same.
- **No role ever pushes to `main`** (`.agents/rules/unattended.md`, "No role
  pushes to `main`"). The rule does not depend on what the code host
  enforces.
- **Work is done when the owner merges its pull request** after checking
  its dev build (`AGENTS.md`, "Standing owner directives", 3).
- **CI's run is the gate of record, and a local gate run is a pre-check**
  (`.agents/rules/unattended.md`, "Claim only what you ran"). Roles may
  build and run the automated tests in their own clone. Manual checks stay
  with the owner.
- **No fact of a caller's machine enters the repository**
  (`.agents/rules/boundaries.md`, "What never appears in the tree or on a
  published page").
- **Names are the specification's defaults**: the role ids and the rule-file
  names. The privacy police, which the specification does not name, takes
  the id `privacy-police` ("Departures").
- **Directives adopted** from the specification's list of owner directives:
  documentation first; nobody checks their own work; prefer a mature
  dependency over hand-rolled code; strict about our own data, never strict
  at the agent; published history is never rewritten; versions are never
  moved by hand; the merge is the release confirmation. They stand in
  `AGENTS.md`, "Standing owner directives".
- **Not adopted:** the directive that money beyond the standing allowance is
  spent only when a person asks, as written.
- **Replaced:** the directive that bans model identity in code or on a
  published page. In its place stands the owner's own rule: the model and the
  tool may be named anywhere, and a session link never appears in anything
  published (`AGENTS.md`, "Standing owner directives"). No role's issue,
  comment or pull-request template carries a session link.

## Slots

### Repository identity and documents

| Slot | Value | Reason |
| :-- | :-- | :-- |
| `ENTRY_POINT` | `AGENTS.md`. `CLAUDE.md` is a link to it | The default, and the file the repository already uses |
| `DOC_LANGUAGE` | English | Every fleet document and `AGENTS.md` are written in it |
| `DATE_POLICY` | No dates in the fleet's own text (`.agents/rules/context.md`) | The default |
| `BEHAVIOUR_SPEC` | `AGENTS.md`, "Product intent — how the app must work" | `docs/architecture.md` names it as the normative behaviour contract |
| `DELIBERATE_TRADES` | The clarifications under `AGENTS.md`, "Product intent — how the app must work", and the trades `docs/architecture.md` records as kept on purpose | Each reads like a defect to a newcomer |
| `STANDING_DECISIONS` | `AGENTS.md`, "Standing owner directives" and "Non-negotiable principles"; the closed paths of `.agents/rules/boundaries.md`; the target-graph bans in `Package.swift`; behaviour pinned by a test with a sensitivity note | The facts a trial must not trip over |
| `ARCHITECTURE_DOC` | `docs/architecture.md` | The layering and mechanism document |
| `DESIGN_DOCS` | `docs/architecture.md` | The default. Storage and the cleanup request are described there, in "Storage" and "Cleanup Mechanism"; no separate stored-format document exists |
| `FORMAT_DOCS` | Empty | No document beyond `docs/architecture.md` fixes a stored or wire format |
| `PRIVACY_PROMISES` | `docs/privacy.md`; `AGENTS.md`, "Before you open a pull request"; `README.md`, "Privacy Model" and "Support"; `SECURITY.md`, "Current Boundaries" | Raw audio stays local. Only transcript text leaves, for cleanup, plus the key-scope request that carries no user content. The app has no telemetry |
| `OWNER_DIRECTIVES` | `AGENTS.md`, "Standing owner directives", "Non-negotiable principles" and "Engineering process" | The owner's recorded rules, the adopted directives among them |
| `RECORDED_ANSWERS` | `.agents/rules/design-vocabulary.md`, "Recorded answers in this tree" | Shapes the tree already argues for |
| `CLOSED_PATHS` | `.agents/rules/boundaries.md`, "Closed paths" | The release pipeline writes them, or they are never committed |
| `LICENCE_POLICY` | GPLv3, with `THIRD-PARTY-NOTICES.md` and the README licence section kept current (`AGENTS.md`, "License compliance is part of every change") | A new dependency stays a person's decision |
| `DELIBERATE_LANGUAGE_EXCEPTIONS` | `.agents/rules/text-residue.md`, "Protected: never a finding", item 5 | Recognising mixed Russian and English speech is the product |
| `PREDECESSOR_QUIRKS` | The comments in `Sources/SlovoCore/Config/Config.swift` and `Sources/SlovoCore/Config/ConfigStore.swift`, carried into `.agents/skills/logic-police/SKILL.md`, "Not findings", and `.agents/skills/issue-court/SKILL.md`, "What you read first" | Behaviour kept on purpose, with no migration |
| `ARCHITECTURE_BANS` | Empty | The recorded bans, the core free of the app shell and the update engine and the import direction of role-tagged modules, are all enforced by the gate (`.agents/rules/verification.md`, "What the gate rejects") |
| `PUBLICATION_RULES` | `.agents/rules/boundaries.md`, "What never appears in the tree or on a published page" | `AGENTS.md`, `SECURITY.md` and the owner's decisions bar them |
| `FLEET_SOURCES` | `.agents/skills/agent-police/SKILL.md`, "Subject" | The owner's decision: the four kinds the specification lists. The kind for a manifest specification names none, because no manifest is adopted |

### Build, gate and toolchain

| Slot | Value | Reason |
| :-- | :-- | :-- |
| `GATE_COMMANDS` | `.agents/rules/verification.md`, "The gate" | What `.github/workflows/swift.yml` runs |
| `GATE_DESCRIPTION` | `.agents/rules/verification.md`, "Which run covers a commit" | A commit on `main` and a pull-request head are covered by different runs |
| `GATE_BLIND_SPOTS` | `.agents/rules/verification.md`, "What a green run does not prove" | |
| `FENCE` | `.agents/rules/verification.md`, "What the gate rejects" | One list, carried verbatim into every verifier brief |
| `TOOLCHAIN_FREE_CHECKS` | `bash -n` over each script; `plutil -lint` needs macOS but not the toolchain (`.agents/rules/verification.md`) | Every other stage needs Xcode |
| `TOOLCHAIN_REFRESH` | `.agents/skills/implementer/SKILL.md`, "The slice loop", step 5 | The owner's decision: CI's run is the gate of record ("The owner's decisions" above) |
| `CONDITIONAL_GUARDS` | `.agents/skills/implementer/SKILL.md`, "The slice loop", the guards a change's content triggers | Recorded rules tied to what a change touches |
| `TEST_SUMMARY_FORMAT` | `.agents/rules/unattended.md`, "Reporting" | The default |
| `TESTING_REFERENCE` | `docs/references/testing-swift.md` | The verified reference `.agents/rules/tests.md` cites |
| `MANUAL_ONLY_TESTS` | `.agents/rules/verification.md`, "What a green run does not prove"; the guard that runs them, `.agents/skills/implementer/SKILL.md`, "The slice loop" | Their stated reason: they call a real system service, skipped on shared CI |
| `SENSITIVITY_NOTE_FORMAT` | `Stated sensitivity: … → RED` | The form the test suite uses |
| `TARGET_PLATFORM_RUNNER` | A Mac with the toolchain `CONTRIBUTING.md` requires, or CI's macOS runner | Where an environment-coupled experiment can run |
| `ACCEPTANCE_PLATFORM` | A Mac with Apple Silicon, on the app's supported macOS | `README.md` and `CONTRIBUTING.md` |
| `MODULE_LIST_SOURCE` | `Package.swift` | The package manifest lists every target |

### Language specifics for the police

| Slot | Value | Reason |
| :-- | :-- | :-- |
| `ESCAPE_HATCH_MARKERS` | `.agents/skills/logic-police/SKILL.md`, "Where to look" | Swift's constructs that bypass its checks |
| `HIDDEN_CALLER_MECHANISMS` | `.agents/skills/abstraction-police/SKILL.md`, "Proof" | What hides a Swift caller from text search |
| `CALLER_RULE` | `.agents/rules/design-vocabulary.md`, "Rules of judgement" and "Recorded answers in this tree" | The default, with the recorded answer on `SlovoTestSupport` |
| `HIGH_CONSEQUENCE_PATHS` | `.agents/skills/logic-police/SKILL.md`, "Where to look" | Where `AGENTS.md`, "Product intent — how the app must work", puts the cost of a defect |
| `ENTRY_POINTS` | `.agents/skills/logic-police/SKILL.md`, "Proof" | Where a reachability trace starts |
| `NAME_CENSUS_CONCEPTS` | `.agents/skills/text-residue-police/SKILL.md`, "Where to look" | The owner's decision: the concepts `AGENTS.md`, "Product intent — how the app must work", names. No glossary exists |
| `CHURN_WINDOW` | `.agents/rules/police.md`, "Shared rules" | The default |
| `EXPERT_KINDS` | `.agents/skills/issue-court/SKILL.md`, "The trial" | The owner's decision: the kinds the specification lists for a court with the toolchain present |
| `BUG_TEMPLATE_FIELDS` | The field labels of `.github/ISSUE_TEMPLATE/bug_report.yml` | The bug template's own field names |

### Security and dependencies

| Slot | Value | Reason |
| :-- | :-- | :-- |
| `THREAT_MODEL` | `.agents/skills/security-police/SKILL.md`, "Threat model" | What every security finding is argued against |
| `SECRET_INVENTORY` | `.agents/skills/security-police/SKILL.md`, "Where to look", the secrets sweep | The secrets the project holds (`docs/release-ci.md`, "One-time owner setup"; `docs/privacy.md`, "Keychain") |
| `PRIVILEGED_PIPELINES` | `.agents/skills/security-police/SKILL.md`, "Where to look", the workflow sweep | They sign, notarize, publish or push |
| `UPDATE_CHANNEL` | `.agents/skills/security-police/SKILL.md`, "Where to look", the update-channel sweep | How installed copies receive updates |
| `RENDERED_OUTPUT` | `.agents/skills/security-police/SKILL.md`, "Where to look", the rendered-output sweep | The owner's decision: `CHANGELOG.md` and the release notes, both rendered from merged pull-request titles |
| `UPDATE_BOT` | `.agents/skills/dependency-police/SKILL.md`, "Dependency Police" | `.github/dependabot.yml` |
| `DEPENDENCY_PROMISES` | `.agents/skills/dependency-police/SKILL.md`, "What every verification checks" | Recorded decisions a bump must not break |
| `QUALITY_GATED_DEPENDENCIES` | `.agents/skills/dependency-police/SKILL.md`, "What every verification checks" | `.github/dependabot.yml` |
| `ADVISORY_SOURCES` | `.agents/skills/dependency-police/SKILL.md`, "Advisories" | The two ecosystems the update bot watches |
| `DEPENDENCY_PRS_PER_RUN` | `.agents/skills/dependency-police/SKILL.md`, "The review queue" | The default |
| `FOLLOW_THROUGH_WINDOW` | `.agents/skills/dependency-police/SKILL.md`, "The review queue" | The default |

### Tracker vocabulary and bounds

| Slot | Value | Reason |
| :-- | :-- | :-- |
| `PROVENANCE_LABEL` | `police-report` | The default. It is on the label list, and no issue template applies it |
| `TRACKER_SCOPE` | `machine` | The owner's decision |
| `AREA_LABELS` | `asr`, `cleanup`, `i18n`, `ux` (`.agents/rules/labels.md`) | The repository's areas |
| `VETO_LABEL` | `wontfix` | The default |
| `NO_TRIAL_LABEL` | `no-trial` | The default. The owner creates it |
| `DEPENDENCY_LABEL` | `dependencies` | The default, applied by the update bot |
| `CAP_TABLE` | `.agents/rules/filing.md`, "Backpressure" | The default columns of the enabled roles |
| `TRIAGE_CEILING` | `.agents/rules/filing.md`, "Independent triage" | The default |
| `WORK_ISSUES_PER_RUN` | Not used | No role cuts work issues |
| `MARKER_NS` | `slovo` | The repository's name |
| `TRUSTED_AUTHOR_TEST` | `.agents/rules/unattended.md`, "Instructions and evidence" | Write-level membership, as the code host reports it on a repository owned by a personal account |
| `POLICE_SKIP_COURT` | Off | The default. Every police report is tried |
| `COMMIT_CONVENTION` | What releases: `cliff.toml`. The kind mapping: `.agents/skills/implementer/SKILL.md`, "The hand-off on an accepted verdict", step 2 | The owner's decision for `tech-debt` and `documentation`. Any header outside `feat:`, `fix:` and `perf:` merges without a release (`AGENTS.md`, "Before you open a pull request") |

### The delivery pipeline

| Slot | Value | Reason |
| :-- | :-- | :-- |
| `PIPELINE_LABELS` | The default names (`.agents/rules/labels.md`) | The owner creates them |
| `BRANCH_NS` | `.agents/skills/pipeline-law/SKILL.md`, "Identity and the discriminator" | The default |
| `SPEC_DIR` | `.agents/skills/pipeline-law/SKILL.md`, "Shape" | The owner's decision |
| `RULE_FILES` | What each stage reads first, as the pipeline law and each stage's role file name it | |
| `IN_FLIGHT` | The default, stated in the pipeline law's "Bounds" | |
| `QUEUE_CAP` | The default, stated in the pipeline law's "Bounds" | |
| `SLICES_PER_DAY` | The default, stated in the pipeline law's "Bounds" | |
| `CI_WAIT_BOUND` | The default, stated in the pipeline law's "Bounds" | |
| `CLERK_REPAIRS_PER_FIRE` | The default, stated in the pipeline law's "Bounds" | |
| `PARKED_HOLDS_SLOT` | Off | The default |
| `CLOSE_ON_MERGE` | Off | The default. A merge closes nothing by itself, and the tracker clerk closes each source once it re-derives as gone |
| `EXTERNAL_REVIEWER` | `.agents/skills/pipeline-law/SKILL.md`, "What a fired stage trusts" | The owner's decision. Its state line is `.agents/rules/markers.md`, "The pipeline clerk's records" |
| `MAX_PARTS` | Off: findings are never split | The default |
| `PLAN_HEADINGS` | `.agents/skills/pipeline-law/SKILL.md`, "The specification shape" | The default. Changes here carry tests |

### Optional roles

| Slot | Value | Reason |
| :-- | :-- | :-- |
| `OPERATION`, `RECORD_WINDOW` | Not used | The record police is off |
| `PUBLISHED_SURFACE`, `SUPPORTED_SURFACES`, `REFERENCE_SOURCES`, `CONFORMANCE_CHECK`, `HYGIENE_SET` | Not used | The published-surface police is off |
| The pipeline law's skill id | `pipeline-law` | The specification names no id for the shared law. A rename is one search and replace |

## What the code host supports

Each capability was measured by a read of this repository where a read
could measure it. A write is measured at acceptance, by the first fire that
makes it.

| # | Capability | Status |
| :-- | :-- | :-- |
| 1 | Read the repository's own identity | Served |
| 2 | List issues by state and label, with full bodies, paginated | Served |
| 3 | Search issue and pull-request bodies for a marker, in every state | Served. Whether the index lags a write: measured at acceptance |
| 4 | Read and write comments byte for byte, hidden markers included, with creation and edit times | Read served: the raw body keeps the hidden comment, the rendered body hides it, and both times are present. Write: measured at acceptance |
| 5 | Create issues with labels; add a label without replacing the set | Measured at acceptance |
| 6 | Close an issue with a reason, a duplicate naming its survivor | The close reason reads back. Write: measured at acceptance |
| 7 | The author's association on issues and comments | Served |
| 8 | Pull requests in every state with body, author, head branch, head repository, labels, merged distinct from closed, close time | Served. The head repository is present on closed pull requests too |
| 9 | CI results per commit: status, conclusion, link, re-run attempts, failed job logs | Served |
| 10 | Closing references in a pull-request body, with documented parsing | The issues a pull request links as closing read back. Needed for the backpressure leave-out only, since `CLOSE_ON_MERGE` is off |
| 11 | Draft pull requests, readable and writable | Read served. Write: measured at acceptance |
| 12 | Remote branches listed by prefix, without lag | Listing served. Lag: measured at acceptance |
| 13 | Labels on pull requests, with label events per pull request | Served: each label applied carries its author and time |
| 14 | Plain comments and review comments on a pull request, each with the author's association | Served |
| 15 | Pushes to non-default branches by the machine identity, with the default branch protected against it | Pushes: measured at acceptance. Protection: not in place. The default branch's rules refuse only its deletion and non-fast-forward updates. The run law forbids a role's push to `main` regardless |
| 16 | Confidential vulnerability records | Private vulnerability reporting is enabled, and the advisory listing is served. Drafting an advisory: measured at acceptance |
| 17 | A scheduler that fires a role on a schedule, on an event and by hand, with a payload and a known session length | Outside the repository: the callers carry it |
| 18 | Issue state and label events with author and time, and what caused a close | Served: close events carry author and time, and the pull request that closed an issue reads back |
| 19 | Close a pull request unmerged and read it back; edit a body and a title and read each back | Closed and merged read back distinctly. Writes: measured at acceptance |
| 20 | The repository's description, topics, licence field and homepage | Served |
| 21 | An issue's parent and ordered parts | Not needed: findings are never split |

## Departures

Each value below differs from the specification's default. A fact of this
repository forced it, the owner chose it, or the specification's own text
was wrong, as each says.

- **The owner added a privacy police**,
  `.agents/skills/privacy-police/SKILL.md`. Slovo's identity is privacy:
  `docs/privacy.md` holds the data-path table, and `AGENTS.md` and
  `README.md` state the promises it keeps. A leak with no adversary would
  otherwise have no owner: the logic police meets one only in passing, and
  the security police owns only the attacker's path. The role extends the
  specification on the police skeleton every police role shares
  (`.agents/rules/police.md`). It owns its row of `.agents/rules/filing.md`,
  "Ownership routing", which the logic police's row and severity table give
  up, and it holds no bound, table or vocabulary another file already holds.
  Its guard goes in the issue body, as `.agents/rules/police.md`, "Shared
  rules", allows a role whose remedy names one.
- **The test kinds keep the testing reference's wording.**
  `.agents/rules/tests.md` takes its kind definitions and measurements word
  for word from `docs/references/testing-swift.md`, "5. The criteria a review
  applies", which records the sources behind each and names
  `.agents/rules/tests.md` the authority. The specification's shorter
  wording says the same. The agent police's subject takes that section, so
  the two texts cannot drift apart unread.
- **No run-log diagnosis rule.** The run law leaves out the rule for a paid
  run that writes its own job log: no fleet role runs or owns a CI job here.
- **A release bookkeeping commit has no gate run.** CI skips the commit the
  release pipeline pushes to `main`, so `.agents/rules/verification.md` maps
  it to its parent's run.
- **An issue's commands never run, not even to re-check it.** The
  specification's tracker clerk re-ran the command or reproduction an issue
  carried, and its court advocate reproduced with no word on whose code.
  Both contradict its run law, under which an issue body is evidence. Both
  roles now write their own check from the claim.
- **Every brief that carries third-party text says so.** The specification
  states the data boundary in its run law, and leaves it out of the triage,
  spec-review, gate and acceptance briefs. Each now states it. The police's
  "fence" is named as the gate's rejection list, so it cannot be read as
  that boundary.
- **The role identity must pass the trusted-author test.** The specification
  lets roles write under a bot identity and never says that an identity
  failing the test makes every marker it writes count for nothing.
- **The security police reads the issue templates.** A template that applied
  `police-report` would let a stranger's issue into the machine population,
  and no role's subject took the templates.
- **A stage's result is a completion line newer than its wake**
  (`.agents/skills/pipeline-law/SKILL.md`, "Where state lives"). The
  specification read a dead run, and a stage's audit, from any completion
  line at the key. A writer re-woken at an unchanged spec hash, or an
  implementer returned at an unchanged tree, then had a line there from its
  earlier round. The pipeline clerk could not see the dead fire, and the
  implementer's audit handed a returned item on without working it. The
  implementer also gains the path for answers that change no work.
- **Whoever takes a fresh round writes `spent_at`.** The specification's law
  requires it, and no role's steps wrote it. The reviewer, the gate, the
  trio and the clerk's outside review now write it in their round's body
  write.
- **A stop on a clone that stays shallow, or without the toolchain, is
  recorded.** The specification stopped such a committing stage before its
  claim and left no record, so the pipeline clerk read the fire as dead and
  re-entered the stage on every sweep. The stage now takes its claim,
  records a condition stop, and ends.
- **Un-sticking names one stage label.** The specification let the owner
  either remove `pipeline/stuck` or apply a stage, and the clerk's comment
  named no stage. A stage applied beside `pipeline/stuck` resumes nothing,
  and a reviewer bound needs the writer. The comment now names the label,
  and the owner makes it the only stage label, then removes
  `pipeline/stuck`.
- **The marker inventory is complete.** Each stage comment kind has its
  step, the skeleton line lives in the pipeline law, the pipeline clerk is
  a reader of the taken marker, and the fields no role branches on are
  marked as a person's.
- **The CI wait is a bound.** It moves a counter, which the specification's
  own definition makes a bound, yet it stopped as a condition. The clerk
  writes no completion line, and the law now says so.
- **The re-entry primitive claims nothing about the code host.** The
  specification stated, with no source, that applying a label already
  present emits no event. Removing the label first wakes the stage either
  way, so the law no longer rests on the claim.
- **The agent police reads `.agents/rules/police.md`.** The specification
  gave it no reader of the shared police rules, so it restated the payload
  rule, had no cost line, and could not carry the fence into a verifier
  brief as `.agents/rules/filing.md` requires.
- **The agent police checks cited headings and the label list.** The
  specification's M11 checked paths alone, so a renamed heading passed every
  read, and nothing compared `.agents/rules/labels.md` with the label list
  that file yields to. M11 now reads each cited heading, and M15 compares
  the label names both ways.
- **A re-trial's way back removes the old state label.** The specification's
  re-trial applies a new label and removes none, so `question` outlived a
  sustained re-trial, and a dismissed one left `invalid` beside it. The
  court cannot tell its own label from one a person set, so removing it is
  the owner's step on the way back.
- **The court has no skip path.** The specification's skip path takes a
  support question, a feature request, a discussion, an empty template or
  spam: a person's issue, which its court section says exists only under
  tracker scope `all`. Under `machine` every issue the court reads is a
  police report, so the path and its `skipped` verdict are left out.
