---
contract_version: 3
---

# Constitution of Akurganow/slovo

## Read first

- AGENTS.md
- docs/architecture.md
- .agents/rules/verification.md "What a green run does not prove"
- .agents/rules/boundaries.md "Closed paths"

## Departments

- abstractions: judged by .agents/rules/design-vocabulary.md
- proportion: judged by .agents/rules/design-vocabulary.md
- text-residue: judged by .agents/rules/text-residue.md
- tests: judged by .agents/rules/tests.md
- privacy: judged by docs/privacy.md

## Fence

- The gate is the `test` job of .github/workflows/swift.yml. It runs `Scripts/diagnose.sh` on a macOS 26 runner for every pull request into main. The stages are the build with warnings as errors and strict concurrency, the test suite, the cleanup benchmark CLI smoke check and `Scripts/lint.sh`.
- The same job then arms the gate self-test and requires the armed run to fail: .github/workflows/swift.yml
- Every push to main runs the same gate through the `test` job of .github/workflows/release.yml, which calls .github/workflows/swift.yml.
- CodeQL for Swift scans every pull request into main and every push to main: .github/workflows/codeql.yml. It is not the gate.
- Packaging in .github/workflows/release.yml and .github/workflows/dev-build.yml builds and signs the app after the gate. It is not the gate.
- The fence does not look for dead code. The `unused_declaration` rule is disabled, and `swiftlint analyze` skips `Tests/`.
- The fence does not run the tests gated off while the `CI` variable is set. They call the real spell checker and the real input-source service.
- The fence does not lint Sources/SlovoObjC. It is outside the Swift settings and the lint stages.
- The fence builds no app bundle, so signing and notarization pass it unproven. So does every effect outside the process: microphone capture, text insertion, the Keychain and the cleanup network call.
- The fence proves one toolchain only, the one on the macOS 26 runner image. Runtime on the macOS 15 floor is checked by hand.
- The complete list is .agents/rules/verification.md "What a green run does not prove".

## Regression proof

- swift build --disable-automatic-resolution
- swift test --disable-automatic-resolution
- Scripts/lint.sh
- Scripts/diagnose.sh

## Not judged

- Package.resolved
- CHANGELOG.md
- Benchmarks/cleanup
- data
- Tests/GateChecksTests/Fixtures
- Tests/SlovoCoreTests/Fixtures
- Sources/SlovoCore/Resources
- Resources/Slovo.icon

## Execution

- Run code only in a copy under the run directory. Never run it in the clone.
- The tree is a Swift package for macOS. Building needs macOS: Package.swift names `swift-tools-version: 6.3` and the macOS 15 platform floor.
- The toolchain the tree expects is Xcode 26.4 or newer, the first with Swift 6.3, as CONTRIBUTING.md "Development Setup" states.
- Dependencies resolve from Package.resolved. Build with `swift build --disable-automatic-resolution`, as .github/workflows/swift.yml and Scripts/diagnose.sh do.
- Every gate stage except `bash -n` and `plutil -lint` writes under `.build/` or touches source file times: .agents/rules/verification.md "What needs the toolchain, and what writes".
- Scripts/build_and_run.sh and Scripts/sign-and-notarize.sh need a code-signing identity. A role never runs them.

## Executor loads

- .agents/rules/tests.md
- .agents/rules/text-residue.md
- .agents/rules/design-vocabulary.md
- .agents/rules/claims.md
- .agents/rules/context.md
- .agents/rules/boundaries.md
- .agents/rules/verification.md

## Labels

- `needs-human` (owner attention): Lawman cannot decide this issue alone. A person decides on it.
- `cleanup`: The text cleanup step: prompts, model selection, output quality
- `ux`: Interface behaviour
- `asr`: Speech recognition
- `i18n`: Language detection, multilingual support
- `tech-debt`: Code that works but costs more to keep than it should
- `ready`: Specified so a person can start from the issue alone; the court's queue skips it
- `dependencies`: Pull requests that update a dependency file
- `github_actions`: Pull requests that update GitHub Actions code
- `swift_package_manager`: Pull requests that update swift_package_manager code
- `dev-build`: Builds a signed dev DMG of this PR; a comment links it and the label removes itself when done
- `bug`: Misbehaviour
- `documentation`: The docs
- `duplicate`: Duplicate of the issue the review names
- `enhancement`: New behaviour
- `good first issue`: Good for newcomers
- `help wanted`: Extra attention is needed
- `invalid`: Reviewed and found wrong
- `question`: A decision is needed from the owner
- `wontfix`: Out of scope. The owner's veto, final; no role touches the issue

## Precedents

- 2026-10-27 #1: A public type in `SlovoCore` that only its own tests reach is dead, unless a written reason names its future caller; a possible future use with no named caller is no such reason. (https://github.com/Akurganow/slovo/issues/120#issuecomment-6431712115)
