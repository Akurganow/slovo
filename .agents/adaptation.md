# Adaptation record

How this repository fills the slots of the fleet's build specification, what
the code host was measured to support, and where a fact of this repository
forced a value other than the specification's default. The agent police
reads this file like any other fleet document. Where a value lives in a rule
file, a role file or the pipeline law, this record names that place and does
not restate the value: the place is the authority.

"Pending the owner" marks a choice the specification leaves open and no fact
of this repository settles. A role that reads such a slot treats it as the
slot's empty value until the owner decides.

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
- **CI's run is the gate of record, and a local gate run is a pre-check**
  (`.agents/rules/unattended.md`, "Claim only what you ran"). Roles may
  build and run the automated tests in their own clone. Manual checks stay
  with the owner.
- **No fact of a caller's machine enters the repository**
  (`.agents/rules/boundaries.md`, "What never appears in the tree or on a
  published page").
- **Names are the specification's defaults**: the role ids and the rule-file
  names.
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
| `PRIVACY_PROMISES` | `docs/privacy.md`; `AGENTS.md`, "Before you open a pull request"; `SECURITY.md`, "Current Boundaries" | Raw audio stays local. Only transcript text leaves, for cleanup, plus the key-scope request that carries no user content |
| `OWNER_DIRECTIVES` | `AGENTS.md`, "Standing owner directives", "Non-negotiable principles" and "Engineering process" | The owner's recorded rules, the adopted directives among them |
| `RECORDED_ANSWERS` | `.agents/rules/design-vocabulary.md`, "Recorded answers in this tree" | Shapes the tree already argues for |
| `CLOSED_PATHS` | `.agents/rules/boundaries.md`, "Closed paths" | The release pipeline writes them, or they are never committed |
| `LICENCE_POLICY` | GPLv3, with `THIRD-PARTY-NOTICES.md` and the README licence section kept current (`AGENTS.md`, "License compliance is part of every change") | A new dependency stays a person's decision |
| `DELIBERATE_LANGUAGE_EXCEPTIONS` | `.agents/rules/text-residue.md`, "Protected: never a finding", item 5 | Recognising mixed Russian and English speech is the product |
| `PREDECESSOR_QUIRKS` | Settings stored by earlier releases keep decoding: an absent field takes its default, and the key trigger's stored values predate the split by key side (the comments in `Sources/SlovoCore/Config/Config.swift` and `Sources/SlovoCore/Config/ConfigStore.swift`) | Behaviour kept on purpose, with no migration |
| `ARCHITECTURE_BANS` | Empty | The recorded bans, the core free of the app shell and the update engine and the import direction of role-tagged modules, are all enforced by the gate (`.agents/rules/verification.md`, "What the gate rejects") |
| `PUBLICATION_RULES` | `.agents/rules/boundaries.md`, "What never appears in the tree or on a published page" | `AGENTS.md`, `SECURITY.md` and the owner's decisions bar them |
| `FLEET_SOURCES` | The default: the harness's documentation for skills, bindings, rule files and links; the skill format specification; the code host's documentation for each behaviour the run law relies on | The default. No manifest specification applies, because no manifest is adopted |

### Build, gate and toolchain

| Slot | Value | Reason |
| :-- | :-- | :-- |
| `GATE_COMMANDS` | `.agents/rules/verification.md`, "The gate" | What `.github/workflows/swift.yml` runs |
| `GATE_DESCRIPTION` | `.agents/rules/verification.md`, "Which run covers a commit" | A commit on `main` and a pull-request head are covered by different runs |
| `GATE_BLIND_SPOTS` | `.agents/rules/verification.md`, "What a green run does not prove" | |
| `FENCE` | `.agents/rules/verification.md`, "What the gate rejects" | One list, carried verbatim into every verifier brief |
| `TOOLCHAIN_FREE_CHECKS` | `bash -n` over each script; `plutil -lint` needs macOS but not the toolchain (`.agents/rules/verification.md`) | Every other stage needs Xcode |
| `TOOLCHAIN_REFRESH` | None. A local gate run is a pre-check, and CI's run on the merge result is the gate of record | The owner's decision. CI takes whatever Xcode its runner image carries |
| `CONDITIONAL_GUARDS` | An update of the speech-recognition engine needs a recognition-quality review on real hardware (`.github/dependabot.yml`; `AGENTS.md`, "Non-negotiable principles", 4 and 6). A dependency change keeps the licence notices current (`AGENTS.md`). A change to user-visible behaviour, setup, privacy or the release workflow updates the docs (`AGENTS.md`). Moving the pinned changelog tool needs the replay in `docs/release-ci.md`, "Version computation" | Recorded rules tied to what a change touches |
| `TEST_SUMMARY_FORMAT` | `.agents/rules/unattended.md`, "Reporting" | The default |
| `TESTING_REFERENCE` | `docs/references/testing-swift.md` | The verified reference `.agents/rules/tests.md` cites |
| `MANUAL_ONLY_TESTS` | The tests enabled only while the `CI` variable is unset (`.agents/rules/verification.md`, "What a green run does not prove"). A change to the spelling and grammar hints or to input-source reading runs them where the toolchain is present | Their stated reason: they call a real system service, skipped on shared CI |
| `SENSITIVITY_NOTE_FORMAT` | `Stated sensitivity: … → RED` | The form the test suite uses |
| `TARGET_PLATFORM_RUNNER` | A Mac with the toolchain `CONTRIBUTING.md` requires, or CI's macOS runner | Where an environment-coupled experiment can run |
| `ACCEPTANCE_PLATFORM` | A Mac with Apple Silicon, on the app's supported macOS | `README.md` and `CONTRIBUTING.md` |
| `MODULE_LIST_SOURCE` | `Package.swift` | The package manifest lists every target |

### Language specifics for the police

| Slot | Value | Reason |
| :-- | :-- | :-- |
| `ESCAPE_HATCH_MARKERS` | Force unwraps, `try!`, `as!`, `unowned`, `fatalError`, `preconditionFailure`; and, against the concurrency checks, `@unchecked Sendable`, `nonisolated(unsafe)` and `assumeIsolated` | Swift's constructs that bypass its checks. `force_unwrapping` is disabled in `.swiftlint.yml`, so nothing fences force unwraps |
| `HIDDEN_CALLER_MECHANISMS` | Protocol witnesses called only through the protocol, `@objc` selectors, string-based class lookup, SwiftUI property wrappers and result builders, `#Preview` blocks, Swift Testing macros, and code a build-tool plugin or the manifest reaches | What hides a Swift caller from text search |
| `CALLER_RULE` | The default: a package's own tests, examples and binaries do not keep its interface alive. `SlovoTestSupport` exists for tests, so its own types used only from tests are not dead | `.agents/rules/design-vocabulary.md`, "Recorded answers in this tree" |
| `HIGH_CONSEQUENCE_PATHS` | The dictation pipeline from key down to insertion; the guard that keeps an empty transcript from the cleanup provider and the pasteboard; the sound-cue queue and its release deadline; mute and restore; the Keychain; the update engine's states; decoding the cleanup provider's response; the encrypted personalization database; the Objective-C exception boundary | Where `AGENTS.md`, "Product intent — how the app must work", puts the cost of a defect |
| `ENTRY_POINTS` | The entry of each executable target in `Package.swift`, and every callback the app hands to the system: the key event tap, menu and Settings actions, notification and update-engine callbacks | Where a reachability trace starts |
| `NAME_CENSUS_CONCEPTS` | Pending the owner | No glossary exists. `AGENTS.md`, "Product intent — how the app must work", names the domain concepts a list could take |
| `CHURN_WINDOW` | The default, stated in the role files that rank churn | |
| `EXPERT_KINDS` | Pending the owner | The court's experts. With the toolchain present a reproduction engineer can run |
| `BUG_TEMPLATE_FIELDS` | The field labels of `.github/ISSUE_TEMPLATE/bug_report.yml` | The bug template's own field names |

### Security and dependencies

| Slot | Value | Reason |
| :-- | :-- | :-- |
| `THREAT_MODEL` | The repository and its history are public. Roles read third-party text and write to the tracker, and provenance comes from markers, never from the author. A person merges. A releasable merge signs, notarizes and publishes an update that installed copies take on their own (`docs/release-ci.md`). Every push to a pull request starts CI on a macOS runner | What every security finding is argued against |
| `SECRET_INVENTORY` | The signing certificate and its password, the notarization key and its identifiers, the update feed's EdDSA private key (`docs/release-ci.md`, "One-time owner setup"); the cleanup provider's API key | The secrets the project holds |
| `PRIVILEGED_PIPELINES` | `.github/workflows/release.yml`, `.github/workflows/dev-build.yml` | They sign, notarize, publish or push |
| `UPDATE_CHANNEL` | Sparkle: `SUFeedURL` and `SUPublicEDKey` in `Resources/Info.plist`, and the appcast the `package` job of `.github/workflows/release.yml` signs | How installed copies receive updates |
| `RENDERED_OUTPUT` | Pending the owner | `CHANGELOG.md` and the release notes are rendered from merged commit headers, which come from pull-request titles anyone can propose. Whether that counts as external data decides whether the security police sweeps it |
| `UPDATE_BOT` | `dependabot[bot]` | `.github/dependabot.yml` |
| `DEPENDENCY_PROMISES` | The comments in `Package.swift` and `.github/dependabot.yml`; the app floor in `Package.swift` `platforms:`; the licence posture | Recorded decisions a bump must not break |
| `QUALITY_GATED_DEPENDENCIES` | The speech-recognition engine, `argmax-oss-swift` | `.github/dependabot.yml` |
| `ADVISORY_SOURCES` | The code host's advisory database for the Swift and GitHub Actions ecosystems, and each dependency's own security advisories | The two ecosystems the update bot watches |
| `DEPENDENCY_PRS_PER_RUN` | The default, stated in the dependency police's role file | |
| `FOLLOW_THROUGH_WINDOW` | The default, stated in the dependency police's role file | |

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
| `COMMIT_CONVENTION` | `feat` releases a minor version; `fix` and `perf` a patch; a `!` header or a `BREAKING CHANGE` footer a major; every other type releases nothing (`cliff.toml`). Kind mapping: `bug` → `fix:`, `enhancement` → `feat:`. `tech-debt` and `documentation`: pending the owner | `cliff.toml` and `AGENTS.md`, "Before you open a pull request". Any header outside `feat:`, `fix:` and `perf:` merges without a release, so the header a `tech-debt` change takes decides whether it ships at once |

### The delivery pipeline

| Slot | Value | Reason |
| :-- | :-- | :-- |
| `PIPELINE_LABELS` | The default names (`.agents/rules/labels.md`) | The owner creates them |
| `BRANCH_NS` | `pipeline/` | The default |
| `SPEC_DIR` | Pending the owner | A per-item directory `main` never carries. No fact of the tree picks its path |
| `RULE_FILES` | What each stage reads first, as the pipeline law and each stage's role file name it | |
| `IN_FLIGHT` | The default, stated in the pipeline law's "Bounds" | |
| `QUEUE_CAP` | The default, stated in the pipeline law's "Bounds" | |
| `SLICES_PER_DAY` | The default, stated in the pipeline law's "Bounds" | |
| `CI_WAIT_BOUND` | The default, stated in the pipeline law's "Bounds" | |
| `CLERK_REPAIRS_PER_FIRE` | The default, stated in the pipeline law's "Bounds" | |
| `PARKED_HOLDS_SLOT` | Off | The default |
| `CLOSE_ON_MERGE` | Off | The default. A merge closes nothing by itself, and the tracker clerk closes each source once it re-derives as gone |
| `EXTERNAL_REVIEWER` | Empty | The default. No outside reviewer is asked. An outside reviewer's comments on a pull request are evidence |
| `MAX_PARTS` | Off: findings are never split | The default |
| `PLAN_HEADINGS` | The default headings, "Tests first" among them | Changes here carry tests |

### Optional roles

| Slot | Value | Reason |
| :-- | :-- | :-- |
| `OPERATION`, `RECORD_WINDOW` | Not used | The record police is off |
| `PUBLISHED_SURFACE`, `SUPPORTED_SURFACES`, `REFERENCE_SOURCES`, `CONFORMANCE_CHECK`, `HYGIENE_SET` | Not used | The published-surface police is off |
| The pipeline law's skill id | `pipeline-law`, pending the owner | The specification names no id for the shared law. A rename is one search and replace |

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

Each value below differs from the specification's default because a fact of
this repository forced it.

- **The test kinds keep the testing reference's wording.**
  `.agents/rules/tests.md` takes its kind definitions and measurements word
  for word from `docs/references/testing-swift.md`, "5. The criteria a review
  applies", which the reference requires to match. The specification's
  shorter wording says the same.
- **No run-log diagnosis rule.** The run law leaves out the rule for a paid
  run that writes its own job log: no fleet role runs or owns a CI job here.
- **A release bookkeeping commit has no gate run.** CI skips the commit the
  release pipeline pushes to `main`, so `.agents/rules/verification.md` maps
  it to its parent's run.
