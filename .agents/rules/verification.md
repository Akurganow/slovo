# Verification: the gate and what it does not prove

The commands CI runs as the gate, what each proves, which CI run covers a
commit, what the gate rejects, and what a green run leaves unproven. CI's own
invocation is recorded in `.github/workflows/swift.yml`. Every other
environment's invocation lives in its caller.

## The gate

The gate is the `test` job of `.github/workflows/swift.yml`. It runs two
commands, and both must hold.

1. `Scripts/diagnose.sh` exits 0. It runs every stage below without failing
   fast, prints `--- PASS: <stage>` or `--- FAIL: <stage>` for each, and ends
   with the complete failure set.
2. The armed gate-integrity run exits non-zero:

   ```sh
   SLOVO_GATE_SELFTEST=red swift test --disable-automatic-resolution --filter gateGoesRedWhenSelfTestArmed
   ```

   It proves the test stage can go red. A test stage that ran nothing would
   pass `Scripts/diagnose.sh` and fail here.

### Stages of `Scripts/diagnose.sh`

| Stage | Run by, and passes when | What it proves |
| :-- | :-- | :-- |
| `swift-build` | `swift build --disable-automatic-resolution`, with cache, configuration and security paths under `.build/`; exits 0 | Every target compiles against the checked-in `Package.resolved`. Every Swift target compiles with warnings as errors, complete strict concurrency checking and actor data-race checks (`Package.swift`), and the SwiftLint build-tool plugin lints it during the build |
| `swift-test` | `swift test --disable-automatic-resolution`, same paths; exits 0 | The test targets build, and every test runs and passes except those gated off when the `CI` variable is set |
| `cleanup-benchmark-cli` | `Scripts/check-cleanup-benchmark-cli.sh`; exits 0 | The benchmark executable runs one sample through its pass-through provider and prints its CSV header and one passing row. It runs the built binary, which `swift-build` never does |
| `strict-lint` | `Scripts/lint.sh`; exits 0 | Every stage of the next table passed |

### Stages of `Scripts/lint.sh`

Each passes when `Scripts/lint.sh` prints `--- PASS: <stage>` for it.

| Stage | What it proves |
| :-- | :-- |
| `explicit-target-imports` | Every module imports only the targets it declares as dependencies. The build of `swift-build` does not check this |
| `bash-syntax:<script>` | `bash -n` parses each script under `Scripts/` |
| `plist-lint` | `plutil -lint` parses `Resources/Info.plist` and `slovo.entitlements` |
| `swiftlint-strict` | SwiftLint's command plugin lints the configuration's whole `included:` set in strict mode, `Package.swift` among it, so a warning fails. The build-tool plugin of `swift-build` lints target by target during the build |
| `swiftlint-compiler-log` | A verbose build, forced to recompile every module under `Sources` and `Tools`, wrote a compiler invocation for each of them to `.build/swiftlint-compiler.log` |
| `swiftlint-analyze` | SwiftLint's analyzer rules pass in strict mode on every Swift file under `Sources` and `Tools`, and the analyzer read as many files as it was given |

### What needs the toolchain, and what writes

- `bash -n` needs nothing but a shell, so it can run anywhere and be
  confirmed. `plutil -lint` needs macOS, not the toolchain. Every other stage
  needs the toolchain `CONTRIBUTING.md`, "Development Setup", requires.
- `bash -n` and `plutil -lint` write nothing, so they may run in place.
- Every other stage writes. Builds, tests and plugins write under `.build/`,
  which version control ignores. `Scripts/check-cleanup-benchmark-cli.sh`
  writes to the temporary directory. `swiftlint-compiler-log` touches the
  modification time of every Swift file under `Sources` and `Tools`. An
  analysis run therefore runs them in a copy under `$RUN`.

## Which run covers a commit

- **A commit on `main`:** the Release run of `.github/workflows/release.yml`
  for that commit. Its `test` job calls `.github/workflows/swift.yml`, and
  the run names that workflow at the same commit among its referenced
  workflows.
- **A release bookkeeping commit on `main`**, headed
  `chore(release): v<version> [skip ci]`, has no run of its own: CI skips
  it. It changes only `CHANGELOG.md` and the version fields of
  `Resources/Info.plist`. The Release run of its parent covers the rest of
  its tree.
- **A pull-request head:** the Swift run of `.github/workflows/swift.yml`
  for that head, which tests the pull request's merge result.
- Cite the run by number and conclusion. A run cancelled because a newer
  push to the same ref superseded it proves nothing. The newer run covers the
  newer head.

## Other checks CI runs

- **CodeQL**, `.github/workflows/codeql.yml`, builds the package for analysis
  and scans it, on every pull request into `main` and every push to `main`.
  It is not the gate. Its open alerts are input to the security police.
- **Packaging.** The Release run's `package` job and
  `.github/workflows/dev-build.yml` build, sign and verify the app after the
  gate passes. They are not the gate, and no fleet role starts them.

## What the gate rejects

This is the fence. A finding about anything here is a misread, because it
cannot exist on a green `main`.

- A compiler warning in any Swift target, an incomplete strict-concurrency
  check, or a static actor data-race violation.
- A violation of any SwiftLint rule `.swiftlint.yml` leaves enabled, in
  strict mode: every opt-in and analyzer rule except the disabled list, and
  the two construct rules under `custom_rules`
  (`.agents/rules/text-residue.md`, "The fence").
- An import of a target a module does not declare.
- What the source-tree scans under `Tests/GateChecksTests` refuse: a
  cleaner, transcriber or injector source that imports the database library
  or a sibling backend; a logger interpolation that makes a payload value
  public; any number of call sites of the update's install-and-relaunch
  other than one; and a `.gitignore` that would admit a seed file, a local
  database or key material.
- A script that does not parse, and a plist or entitlements file that does
  not lint.
- Any defect a test in the suite turns red.

## What a green run does not prove

- **Tests gated off CI.** Tests enabled only while the `CI` variable is
  unset, because they call the real spell checker or the real input-source
  service, are skipped on CI. A report counts them among the ignored tests
  and names them. A run where the toolchain is present runs them.
- **The test tree under the analyzer.** `swiftlint analyze` never reads
  `Tests/`: SourceKit crashes expanding the Swift Testing macros
  (`Scripts/lint.sh`, `generate_swiftlint_compiler_log`). A report counts
  that check as not run. No link to the upstream defect is recorded in the
  tree. For the same reason `unused_declaration` is disabled, so no stage
  looks for dead code.
- **Disabled lint rules.** Every rule `.swiftlint.yml` disables fences
  nothing, `force_unwrapping` among them.
- **The Objective-C target.** `Sources/SlovoObjC` is outside the Swift
  settings and the lint stages.
- **The app's floor.** CI runs only on its macOS 26 image. Runtime on the
  oldest supported macOS is checked by hand (`docs/development.md`, "Manual
  macOS 15 floor check (oldest-OS-only)").
- **Effects outside the process.** Microphone capture, the Accessibility
  and Input Monitoring grants, the global key tap, insertion into the
  focused app, muting system output, the Keychain, the cleanup provider's
  network call and the update feed are proven only by a live run of a built
  app: the owner's check of a dev build (`AGENTS.md`, "Standing owner
  directives", 3).
- **Recognition quality.** No stage measures recognition of mixed Russian
  and English speech against its baseline (`AGENTS.md`, "Non-negotiable
  principles", 6).
- **Cleanup quality.** The benchmark stage runs only the pass-through
  provider. It proves the harness runs, not that cleanup is good.
- **Signing and packaging.** The gate builds no app bundle. Signing,
  notarization and stapling are proven only by the packaging jobs.
- **Another toolchain.** CI's runner image chooses its Xcode. A green there
  proves that toolchain only (`.agents/rules/unattended.md`, "Claim only what
  you ran").

This file describes `.github/workflows/swift.yml`, `Scripts/diagnose.sh`,
`Scripts/lint.sh` and the workflows they serve. Where CI and this file
disagree, CI is right and this file is stale.
