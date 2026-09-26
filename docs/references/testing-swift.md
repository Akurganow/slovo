# Testing in Swift: the framework, the smells, and what a test must earn

## Purpose

The evidence base for reviewing Slovo's test suite: what Swift Testing actually
guarantees about isolation, parallelism and skipping; what the testing
literature says makes a test flaky, brittle, redundant, over-specified or out
of proportion to what it guards, and what a suite's size costs; what
mutation analysis measures and costs; and how Slovo's own rules meet all of it.
It ends with the review criteria, each tied to its sources.

Every claim cites a source that was read, not recalled, on 2026-09-26. Quotes
are verbatim. Where a fact rests on a forum post or a secondary page rather than
normative documentation, the text says so. Repository facts are cited at commit
`734435a` (`main` on that date).

Slovo's floor is what matters. `Package.swift:1` declares `swift-tools-version:
6.3`, and `CONTRIBUTING.md:10` requires "Xcode 26.4 or newer, the first release
carrying the Swift 6.3 toolchain". CI runs the gate on `macos-26` only
(`.github/workflows/swift.yml`). Where Swift Testing's `main` differs from the
6.3 release, both are stated.

---

## 1. Swift Testing as Slovo runs it

Swift Testing revisions read: `main` at
[`ea85075`](https://github.com/swiftlang/swift-testing/tree/ea850751b69a18e332619feab7777ebc54f39c62)
and the tags `swift-6.3.3-RELEASE` and `swift-6.4.0-RELEASE`. Apple's hosted
articles were read through their DocC JSON and matched the repository's DocC
sources for every article compared. No test file in the repository imports
XCTest (`grep -rl "import XCTest" Tests` finds none), so everything below
concerns Swift Testing.

### 1.1 Tests run in parallel, in one process, in no fixed order

- [Running tests serially or in parallel](https://developer.apple.com/documentation/testing/parallelization):
  > By default, tests run in parallel with respect to each other. Parallelization
  > is accomplished by the testing library using task groups, and tests generally
  > all run in the same process.
- Synchronous tests too, unlike XCTest —
  [WWDC24 10195, Go further with Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10195/):
  > Swift Testing runs test functions in parallel by default, regardless of whether
  > they are synchronous or asynchronous. This is a notable difference from XCTest,
  > which only supports parallelization using multiple processes, each running one
  > test at a time.
- The cases of a parameterized test run in parallel with each other
  ([ParameterizedTesting.md](https://raw.githubusercontent.com/swiftlang/swift-testing/ea850751b69a18e332619feab7777ebc54f39c62/Sources/Testing/Testing.docc/ParameterizedTesting.md)),
  and so do the tests inside one suite
  ([OrganizingTests.md](https://raw.githubusercontent.com/swiftlang/swift-testing/ea850751b69a18e332619feab7777ebc54f39c62/Sources/Testing/Testing.docc/OrganizingTests.md)).
- A global actor does not serialize tests —
  [ST-0003](https://raw.githubusercontent.com/swiftlang/swift-evolution/d7b4e0ad0946bc34d475130aae0fe6edaa77f867/proposals/testing/0003-make-serialized-trait-api.md):
  > global actors do not ensure that a specific test runs entirely to completion
  > before another begins.
- Order is randomized on purpose —
  [WWDC24 10195](https://developer.apple.com/videos/play/wwdc2024/10195/):
  > the order in which your tests run is randomized. This helps surface hidden
  > dependencies between tests
  In the code, the runner iterates `Graph.children`, a dictionary
  ([Graph.swift L30](https://raw.githubusercontent.com/swiftlang/swift-testing/ea850751b69a18e332619feab7777ebc54f39c62/Sources/Testing/Support/Graph.swift);
  [Runner.swift L362-364](https://raw.githubusercontent.com/swiftlang/swift-testing/ea850751b69a18e332619feab7777ebc54f39c62/Sources/Testing/Running/Runner.swift),
  the same logic at L310-312 in 6.3.3), and dictionary order follows
  [`Hasher`](https://developer.apple.com/documentation/swift/hasher), which "is
  usually randomly seeded, which means it will return different values on every
  new execution of your program." Under `--no-parallel` or inside a
  `.serialized` subtree, children run in source order (Runner.swift, L366).

### 1.2 `.serialized` reaches only its own branch

- [Running tests serially or in parallel](https://developer.apple.com/documentation/testing/parallelization),
  identical in the repository's
  [Parallelization.md](https://raw.githubusercontent.com/swiftlang/swift-testing/ea850751b69a18e332619feab7777ebc54f39c62/Sources/Testing/Testing.docc/Parallelization.md):
  > When added to a parameterized test function, this trait causes that test to run
  > its cases serially instead of in parallel. When applied to a non-parameterized
  > test function, this trait has no effect. When applied to a test suite, this
  > trait causes that suite to run its contained test functions and sub-suites
  > serially instead of in parallel.
  >
  > This trait doesn't affect the execution of a test relative to its peers or to
  > unrelated tests.
- [WWDC24 10195](https://developer.apple.com/videos/play/wwdc2024/10195/):
  > Swift is still free to run other unrelated tests in parallel with these
  > serialized tests
- In the 6.3.3 release the trait turns parallelization off in a task-local
  configuration for its own subtree only
  ([ParallelizationTrait.swift L42-48 @ 6.3.3](https://raw.githubusercontent.com/swiftlang/swift-testing/swift-6.3.3-RELEASE/Sources/Testing/Traits/ParallelizationTrait.swift)).
- The maintainer calls this scope confusing, and names the only way to
  serialize tests that share state —
  [Swift Forums, Pre-Pitch: Data-Dependent Test Serialization, post 1](https://forums.swift.org/t/81251)
  (a forum post, not documentation):
  > Today, the only way to ensure that all these tests run serially is to nest them
  > all in a single suite marked .serialized. … it's not clear that .serialized only
  > applies locally rather than globally.
- A process-wide `.serialized(for:)` exists on `main` and in the 6.4.0 tag only
  as `@_spi(Experimental)`, and is absent from 6.3.3 (0 occurrences of
  `serialized(for` in that tag's `ParallelizationTrait.swift`). It is not
  available to this repository.

| Applied to | Effect |
| :-- | :-- |
| a parameterized test | its cases run one at a time |
| a non-parameterized test | none |
| a suite | its children run one at a time, recursively |
| any test in another branch | none: it may still run concurrently with the serialized suite |

### 1.3 Process-global state is shared by every test

- Each instance `@Test` runs on a fresh suite instance —
  [Organizing test functions with suite types](https://developer.apple.com/documentation/testing/organizingtests):
  > If a test suite type contains multiple test functions declared as instance
  > methods, each one is called on a distinct instance of the type.
  That isolates instance state only. Statics and globals, the environment block,
  standard I/O and the working directory belong to the process.
- What the documentation says about shared state —
  [Migrating a test from XCTest](https://developer.apple.com/documentation/testing/migratingfromxctest):
  > If your tests use shared state such as global variables, you may see
  > unexpected behavior including unreliable test outcomes when you run tests in
  > parallel.
  and the remedy it names is `.serialized` on the suite, which reaches only that
  suite (§1.2).
- The environment block, by name, appears only in maintainers' forum posts, not
  in the documentation —
  [Pre-Pitch thread, posts 1 and 5](https://forums.swift.org/t/81251):
  > Canonical examples of such state are the standard I/O streams and the
  > environment block, either of which can be mutated by any thread at any time
  > outside the control of Swift's structured concurrency.

  > the environment block, which thanks to POSIX is a big unavoidable ball of
  > use-after-free bugs.
- Nothing in the Swift Testing documentation or the WWDC24 transcripts mentions
  `UserDefaults` (grep over the DocC sources at `ea85075`).
- Apple's stated preference is refactoring over serializing —
  [WWDC24 10195](https://developer.apple.com/videos/play/wwdc2024/10195/):
  > If necessary, you can run tests serially but we recommend refactoring your
  > tests so they can run in parallel.
- Scoping traits (`TestScoping`, Swift 6.1 / Xcode 16.3) consolidate set-up and
  tear-down but serialize nothing; the proposal steers global state toward
  `@TaskLocal`
  ([ST-0007](https://raw.githubusercontent.com/swiftlang/swift-evolution/d7b4e0ad0946bc34d475130aae0fe6edaa77f867/proposals/testing/0007-test-scoping-traits.md)).
  The built-in `.taskLocal` trait is Swift 6.5 and unreleased.
- Exit tests (Swift 6.2 / Xcode 26.0) run their body in a child process
  ([exit-testing.md](https://raw.githubusercontent.com/swiftlang/swift-testing/ea850751b69a18e332619feab7777ebc54f39c62/Sources/Testing/Testing.docc/exit-testing.md)):
  > the testing library starts a new process with the same executable as the
  > current process.
  The documentation presents them for code that terminates the process; the
  isolation is a side effect, not a stated purpose.

### 1.4 Skipping, known issues and time

- `.enabled(if:)` is evaluated while the run is planned, before any test starts,
  and may be evaluated more than once
  ([Trait.swift L35-36](https://raw.githubusercontent.com/swiftlang/swift-testing/ea850751b69a18e332619feab7777ebc54f39c62/Sources/Testing/Traits/Trait.swift),
  [ConditionTrait.swift](https://raw.githubusercontent.com/swiftlang/swift-testing/ea850751b69a18e332619feab7777ebc54f39c62/Sources/Testing/Traits/ConditionTrait.swift),
  [EnablingAndDisabling.md](https://raw.githubusercontent.com/swiftlang/swift-testing/ea850751b69a18e332619feab7777ebc54f39c62/Sources/Testing/Testing.docc/EnablingAndDisabling.md)).
  Its stated purpose is the environment:
  > you might want to write a test that only runs on devices with particular
  > hardware capabilities, or performs locale-dependent operations.
- An OS version is a declaration, not a runtime check —
  [WWDC24 10179, Meet Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10179/):
  > Use the @available(...) attribute rather than checking at runtime using
  > #available.
- `Test.cancel(_:)` (Swift 6.3 / Xcode 26.4) skips from inside a running test and
  is not a failure
  ([Apple](https://developer.apple.com/documentation/testing/test/cancel(_:sourcelocation:))).
- `withKnownIssue` keeps a failing test running and reports when it starts
  passing, which Apple prefers to disabling —
  [WWDC24 10195](https://developer.apple.com/videos/play/wwdc2024/10195/):
  > withKnownIssue is a better option in this case. The test will continue to run
  > … When the issue is fixed and an error is no longer thrown, you'll be notified
  For a nondeterministic failure, the documentation puts the fix first —
  [known-issues.md](https://raw.githubusercontent.com/swiftlang/swift-testing/ea850751b69a18e332619feab7777ebc54f39c62/Sources/Testing/Testing.docc/known-issues.md):
  > If you discover a bug such as a race condition, the ideal resolution is to fix
  > the underlying problem
- `.timeLimit` takes whole minutes —
  [TimeLimitTrait.swift](https://raw.githubusercontent.com/swiftlang/swift-testing/ea850751b69a18e332619feab7777ebc54f39c62/Sources/Testing/Traits/TimeLimitTrait.swift):
  > Test timeouts do not support high-precision, arbitrarily short durations due to
  > variability in testing environments.

### 1.5 Tolerances, and what stays in XCTest

- Swift Testing has no tolerance comparison —
  [Migrating a test from XCTest](https://developer.apple.com/documentation/testing/migratingfromxctest):
  > The testing library doesn't provide an equivalent of
  > `XCTAssertEqual(_:_:accuracy:_:file:line:)`. To compare two numeric values
  > within a specified accuracy, use `isApproximatelyEqual()` from swift-numerics.
  swift-numerics is not a dependency of this package; the manual form is
  `#expect(abs(a - b) <= tolerance)`.
- UI automation and performance measurement (`measure`, `XCTMetric`) exist only
  in XCTest ([WWDC24 10179](https://developer.apple.com/videos/play/wwdc2024/10179/)).
  Both frameworks can share a target (MigratingFromXCTest.md L44-46), but
  cross-framework assertions are off below toolchain 6.4, so an `XCTAssert`
  inside a `@Test` is ignored on this repository's floor
  ([MigratingFromXCTest.md L96-111](https://raw.githubusercontent.com/swiftlang/swift-testing/ea850751b69a18e332619feab7777ebc54f39c62/Sources/Testing/Testing.docc/MigratingFromXCTest.md)).

### 1.6 A test target can import an executable target

- [SwiftPM CHANGELOG, Swift 5.5](https://raw.githubusercontent.com/swiftlang/swift-package-manager/main/CHANGELOG.md):
  > Test targets can now link against executable targets as if they were
  > libraries, so that they can test any data structures or algorithms in them.
  > All the code in the executable except for the main entry point itself is
  > available to the unit test. … This feature is available to tests defined in
  > packages that have a tools version of `5.5` or newer.
- None of this repository's test targets depends on the `slovo` executable
  (`Package.swift:101-124`). What that leaves untestable is recorded in §4.2.

---

## 2. What the literature says a test must not do

### 2.1 Flaky and environment-coupled tests

- Definition — [Micco, Flaky Tests at Google and How We Mitigate Them (2016)](https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html):
  > We define a "flaky" test result as a test that exhibits both a passing and a
  > failing result with the same code.
- A platform dependency counts as flakiness even when its outcome is consistent
  on one machine —
  [Parry et al., A Survey of Flaky Tests, ACM TOSEM 31(1) (2022)](https://eprints.whiterose.ac.uk/id/eprint/230095/1/parry2021.pdf),
  Table 4:
  > Platform Dependency Test depends on some particular functionality of a
  > specific operating system, library version, hardware vendor, etc.. While such
  > tests may produce a consistent outcome on a given platform, they are still
  > considered flaky
  The mechanism, p. 2:
  > it relies on the behavior of a particular implementation of an
  > underdetermined specification
- Meszaros names the consistent variant — [Fragile Test, Context Sensitivity](http://xunitpatterns.com/Fragile%20Test.html)
  (web draft of the book):
  > Context Sensitivity occurs when a test fails because the state or behavior of
  > the context in which the SUT executes has changed in some way. … We need to
  > control all the inputs of the SUT if our tests are to be deterministic.
- Root causes, by share of 161 classified fixes —
  [Luo et al., An Empirical Analysis of Flaky Tests, FSE 2014](http://mir.cs.illinois.edu/marinov/publications/LuoETAL14FlakyTestsAnalysis.pdf),
  pp. 4-5:
  > 74 out of 161 (45%) commits are from the Async Wait category. … 32 out of 161
  > (20%) … Concurrency … 19 out of 161 (12%) … Test Order Dependency
  The order-dependency mechanism, p. 5:
  > the tests depend on a shared state that is not properly setup or cleaned.
  Unchecked system state appears in Parry et al. §5.1.7:
  > unchecked dependencies upon the system state (e.g., reading/modifying
  > environment variables)
- Fixes that work, and fixes that only lower the odds — Luo et al., §5.1:
  > Using a waitFor is the most efficient and effective way to fix Async Wait
  > flaky tests.

  > the fixes where sleep calls are used … are only decreasing the chance of a
  > flaky failure
  [Fowler, Eradicating Non-Determinism in Tests (2011)](https://martinfowler.com/articles/nonDeterminism.html):
  > Never use bare sleeps to wait for asynchonous responses: use a callback or
  > polling. … Always wrap the system clock, so it can be easily substituted for
  > testing.
- A timing assertion fails on a slower machine regardless of bugs — Parry et
  al., p. 2:
  > Because the time taken may vary depending on the machine specification, it can
  > fail regardless of any genuine bugs
- **The caution that governs every flaky finding** — Luo et al., Table 1:
  > Some fixes to flaky tests (24%) modify the CUT, and most of these cases (94%)
  > fix a bug in the CUT. … Flaky tests should not simply be removed or disabled
  > because they can help uncover bugs in the CUT.

### 2.2 Change-detector and brittle tests

- Definition — [Eagle, Change-Detector Tests Considered Harmful (2015)](https://testing.googleblog.com/2015/01/testing-on-toilet-change-detector-tests.html):
  > This is a change-detector test—it is a transformation of the same information
  > in the code under test—and it breaks in response to any change to the
  > production code, without verifying correct behavior of either the original or
  > modified production code.

  > Change detectors provide negative value … These tests should be re-written or
  > deleted.
- Brittle — [Software Engineering at Google, ch. 12 Unit Testing](https://abseil.io/resources/swe-book/html/ch12.html):
  > a brittle test is one that fails in the face of an unrelated change to
  > production code that does not introduce any real bugs.

  > the ideal test is unchanging: after it's written, it never needs to change
  > unless the requirements of the system under test change.
- Test state, not interactions — same chapter:
  > interaction tests check how a system arrived at its result, whereas usually you
  > should care only what the result is.
- The recorded exceptions, when how is the requirement —
  [Trenk, Test Behavior, Not Implementation (2013)](https://testing.googleblog.com/2013/08/testing-on-toilet-test-behavior-not.html):
  > There are many cases where you do want to test implementation details (e.g. you
  > want to ensure that your implementation reads from a cache instead of from a
  > datastore)
  [Trenk, Testing State vs. Testing Interactions (2013)](https://testing.googleblog.com/2013/03/testing-on-toilet-testing-state-vs.html):
  > differences in the number or order of calls would cause undesired behavior,
  > such as side effects … latency … or multithreading issues
- Structure-insensitivity as a property to trade, not an absolute —
  [Beck, Test Desiderata](https://testdesiderata.com/):
  > Structure-insensitive — tests should not change their result if the structure
  > of the code changes.

  > Behavioral — tests should be sensitive to changes in the behavior of the code
  > under test.
  The same page presents the twelve properties as trade-offs.
- Mutation analysis produces change-detectors when misused —
  [Petrović et al., Practical Mutation Testing at Scale](https://arxiv.org/pdf/2102.11378):
  > these tests, if written and added, would even have a negative impact because
  > their change-detector nature (specifically testing the current implementation
  > rather than the specification) violates testing best practices and causes
  > brittle tests and false alarms.

### 2.3 Redundant tests

- Test implication —
  [van Deursen et al., Refactoring Test Code (XP 2001)](https://ir.cwi.nl/pub/4324/04324D.pdf),
  Smell 11:
  > test A and B cover the same production code, and A fails if and only if B
  > fails.
- One condition, one test — [Meszaros, Principles of Test Automation](http://xunitpatterns.com/Principles%20of%20Test%20Automation.html):
  > Having several tests verify the same functionality is likely to increase test
  > maintenance costs and won't likely improve quality very much.
- A definition by requirements —
  [Shi et al., Balancing Trade-Offs in Test-Suite Reduction, FSE 2014](http://mir.cs.illinois.edu/marinov/publications/ShiETAL14ReductionEvolution.pdf):
  > A test t from a test suite T is redundant if t satisfies only the requirements
  > satisfied by the other T \ {t} tests from the test suite.
  and why the requirement must be killed mutants rather than covered lines:
  > traditional reduction based on statement coverage can reduce test-suite size
  > on average 62.9% but loses up to 20.5% in killed mutants. In contrast, the
  > reduction based on killed mutants achieves no loss in killed mutants
- Deliberate redundancy is a recorded exception —
  [SWE ch. 12](https://abseil.io/resources/swe-book/html/ch12.html):
  > such redundancy can be valuable: without it, a gap in test coverage could be
  > introduced if one of the library's users (and its tests) were ever removed.

### 2.4 Over-specified tests

- [Meszaros, Fragile Test, Overspecified Software](http://xunitpatterns.com/Fragile%20Test.html):
  > the tests describe how the software should do something, not what it should
  > achieve.
  and Sensitive Equality:
  > the test is sensitive to behavior that it is not in the business of verifying.
- [Kent, Prefer Narrow Assertions in Unit Tests (2024)](https://testing.googleblog.com/2024/04/prefer-narrow-assertions-in-unit-tests.html):
  > Broad assertions should only be used for unit tests that care about all of the
  > implicitly tested behaviors, which should be a small minority of unit tests.
- An accepted range narrower than the valid one is a flakiness category of its
  own — Parry et al., Table 4:
  > Too Restrictive Range Test where some of the valid output range falls outside
  > of what is accepted in its assertions.
  Luo et al., §5.1, on the concurrency fix of that shape:
  > The fix is to account for all valid behaviors in the assertion.
- Floating point — Luo et al., p. 9:
  > it is good practice to have test assertions as independent as possible from
  > floating-point results.
  A tolerance must be justified by the computation —
  [Dawson, Comparing Floating Point Numbers, 2012 Edition](https://randomascii.wordpress.com/2012/02/25/comparing-floating-point-numbers-2012-edition/):
  > There is no silver bullet. You have to choose wisely.
- Golden and diff tests need a reader —
  [SWE ch. 14 Larger Testing](https://abseil.io/resources/swe-book/html/ch14.html):
  > Someone must understand the results enough to know whether any differences are
  > expected.

### 2.5 Suite economics

- [SWE ch. 11 Testing Overview](https://abseil.io/resources/swe-book/html/ch11.html):
  > A bad test suite can be worse than no test suite at all.

  > Our experience suggests that as you approach 1% flakiness, the tests begin to
  > lose value.

  > Brittle tests—those that over-specify expected outcomes or rely on extensive
  > and complicated boilerplate—can actually resist change.
- [Meszaros, High Test Maintenance Cost](http://xunitpatterns.com/High%20Test%20Maintenance%20Cost.html):
  > Too much effort is spent maintaining existing tests.
- Deleting without accounting for protection is its own smell —
  [Meszaros, Erratic Test](http://xunitpatterns.com/Erratic%20Test.html):
  > We may be tempted to removed the failing test from the suite to "Keep the Bar
  > Green" but this would result in an (intentional) Lost Test
- Merging is not automatically a saving — Luo et al., §5.1:
  > Merging dependent tests makes tests larger and thus hurts their readability and
  > maintainability
  and duplication in tests is tolerated for clarity —
  [SWE ch. 12](https://abseil.io/resources/swe-book/html/ch12.html):
  > A little bit of duplication is OK in tests so long as that duplication makes
  > the test simpler and clearer.
- A test has a price to weigh at deletion as well as at birth —
  [Picard, Cost-Benefit Analysis of a Test (2008)](https://testing.googleblog.com/2008/03/cost-benefit-analysis-of-test.html):
  > This cost should be balanced against the benefits of the test when deciding
  > whether a test should be deleted or whether it should be written in the first
  > place.

### 2.6 Proportion: what a test validates, and what that costs

- A test's scope is the code it checks, not the code it runs —
  [SWE ch. 11](https://abseil.io/resources/swe-book/html/ch11.html):
  > when we talk about unit tests as being narrowly scoped, we're referring to
  > the code that is being validated, not the code that is being executed.
  and the smallest test that can check it is preferred:
  > encourage engineers to always write the smallest possible test for a given
  > piece of functionality. A test's size is determined not by its number of
  > lines of code, but by how it runs, what it is allowed to do, and how many
  > resources it consumes.
- [Beck, Test Desiderata](https://testdesiderata.com/):
  > Writable — tests should be cheap to write relative to the cost of the code
  > being tested.
- When only a collaborator can break it, the collaborator is what to test —
  [JUnit 4 FAQ](https://junit.org/junit4/faq.html):
  > The only way myMethod could break would be if myCollaborator.anotherMethod()
  > were broken. In that case, test myCollaborator, and not the current class.
- Humble Object: the decision moves to code a cheap test reaches, and the
  hard-to-test adapter stays thin —
  [Meszaros, Humble Object](http://xunitpatterns.com/Humble%20Object.html):
  > We extract all the logic from the hard-to-test component into a component
  > that is testable via synchronous tests.

  > As a result, it requires only one or two tests to verify it does this
  > correctly.
  [Feathers, The Humble Dialog Box (2002)](https://martinfowler.com/articles/images/humble-dialog-box/TheHumbleDialogBox.pdf):
  > When you do that, you end up with two classes: a smart tested class and a
  > humble dialog class.
  Apple teaches the same move —
  [WWDC18 417, Testing Tips & Tricks](https://developer.apple.com/videos/play/wwdc2018/417/):
  > I probably only need one or two tests that show that the timer delay works
  > properly. And, for the rest of the class, I can call the show next place
  > method directly and not need to mock a timer scheduler at all.

  > we can avoid artificial delays in our tests, since they should never be
  > necessary.
- A platform value is the platform's, and it moves —
  [Human Interface Guidelines, Color](https://developer.apple.com/design/human-interface-guidelines/color):
  > Avoid hard-coding system color values in your app. Documented color values
  > are for your reference during the app design process. The actual color
  > values may fluctuate from release to release, based on a variety of
  > environmental variables.
  Rendered output depends on the platform that draws it —
  [Android Developers, Screenshot testing](https://developer.android.com/training/testing/ui-tests/screenshot):
  > Screenshot tests rely on low-level platform APIs to draw specific features
  > like text or shadows, and platforms can implement those in different ways.
- The counterweights. Where the visible result is the requirement, the same page
  recommends screenshots, kept few:
  > You should minimize the number of screenshot tests while maximizing the
  > feedback and coverage for regressions.
  A real dependency that breaks the product is a signal —
  [SWE ch. 13](https://abseil.io/resources/swe-book/html/ch13.html):
  > Using real implementations can cause your test to fail if there is a bug in
  > the real implementation. This is good!
  and one test at the seam with the real thing is defensible —
  [Vocke, The Practical Test Pyramid (2018)](https://martinfowler.com/articles/practical-test-pyramid.html):
  > You might argue that this is testing the framework and something that I
  > should avoid as it's not our code that we're testing. Still, I believe
  > having at least one integration test here is crucial.
- None of the sources read here states "do not test the platform" as a rule in
  those words; the statements above are the nearest primary ones.

### 2.7 A regression test after its fix

- A fix carries the missing case —
  [SWE ch. 12](https://abseil.io/resources/swe-book/html/ch12.html):
  > Fixing a bug is much like adding a new feature: the presence of the bug
  > suggests that a case was missing from the initial test suite, and the bug fix
  > should include that missing test case.
- Suites change by refactoring, deletion and addition more than by repair —
  [Pinto, Sinha, Orso, Understanding myths and realities of test-suite evolution, FSE 2012](https://doi.org/10.1145/2393596.2393634)
  (abstract; the full text was not reachable):
  > our findings show that test repair is just one possible reason for
  > test-suite evolution, whereas most changes involve refactorings, deletions,
  > and additions of test cases.
- Subsumption, and trimming over deleting —
  [Beck, Composable Tests (2025)](https://newsletter.kentbeck.com/p/composable-tests):
  > Notice that test2 can't pass if test1 fails. All non-compliant programs caught
  > by test1 will also be caught by test2.

  > Deleting test1 loses us another property from the Test Desiderata—tests
  > should be specific.
  [Vocke](https://martinfowler.com/articles/practical-test-pyramid.html):
  > I delete high-level tests that are already covered on a lower level (given
  > they don't provide extra value).
- "It never failed" is not grounds —
  [Memon et al., Taming Google-Scale Continuous Testing, ICSE-SEIP 2017](https://research.google.com/pubs/archive/45861.pdf):
  > We found (Table II) that 91.3% PASSED at least once and never FAILED even once
  > during their execution history.
  The paper's proposal is to run such tests less often ("executed less
  frequently"); it does not propose deleting them.
- No study read here follows regression tests added with fixes over time to
  measure whether they later become redundant; the sweep over fix-born tests
  (§5) rests on the principles above and on the reduction studies (§2.3).

---

## 3. Mutation analysis

### 3.1 What it measures

- [Jia & Harman, An Analysis and Survey of the Development of Mutation Testing, IEEE TSE (2011)](http://crest.cs.ucl.ac.uk/fileadmin/crest/sebasepaper/JiaH10.pdf):
  > If the result of running p′ is different from the result of running p for any
  > test case in T, then the mutant p′ is said to be 'killed', otherwise it is said
  > to have 'survived'.

  > The mutation score (MS) is the ratio of the number of killed mutants over the
  > total number of non-equivalent mutants.

  > there are some mutants that can never be killed, because they always produce
  > the same output as the original program. These mutants are called Equivalent
  > Mutants. … Empirical results indicate that there are 10% to 40% of mutants
  > which are equivalent
- Redundancy through the kill matrix —
  [Ammann, Delamaro & Offutt, Establishing Theoretical Minimal Sets of Mutants, ICST 2014](https://www.albany.edu/faculty/offutt/research/papers/MiniMutant-ICST2014.pdf):
  > If two tests kill precisely the same set of mutants, we consider the tests to
  > be indistinguished

  > Note that a given test need not be part of any minimal test set.
  The set depends on the mutants chosen:
  > Note that T̂ depends on exactly which mutants are used.

### 3.2 What it costs, and how Google made it usable

- [Petrović & Ivanković, State of Mutation Testing at Google, ICSE-SEIP 2018](https://storage.googleapis.com/gweb-research2023-media/pubtools/4203.pdf):
  > At present it is infeasably expensive to compute the absolute mutation score
  > for the codebase at any given fixed point.

  > Only lines affected by the diff under review that are covered and are not arid
  > are mutated.
- [Petrović et al., Does mutation testing improve testing practices?, ICSE 2021](https://arxiv.org/pdf/2103.07189):
  > RQ3: Mutants are coupled with 70% of high-priority bugs

  > RQ4: Mutants are heavily redundant. In more than 90% of cases, either all
  > mutants in a line are killed, or none are.
  The practice reports mutants to a reviewer rather than a score, and "any one
  productive mutant is sufficient".

### 3.3 Tools for Swift

Read at the commits named; licenses read from each `LICENSE` file.

| Tool | License | SwiftPM | Swift Testing | Status |
| :-- | :-- | :-- | :-- | :-- |
| [Muter](https://github.com/muter-mutation-testing/muter) @ `7f1f258` | MIT | yes: `swift test`, then `--skip-build` once per mutant | Swift Testing's "with N issue" summary is matched only on `master` since 2026-07-21; the last tag `16` (2023-09-16), which Homebrew installs, matches only XCTest's, xcodebuild's and Buck's failure lines and scores any other non-zero exit that shows no build error as "mutant killed (runtime error)" | last commit 2026-07-21 |
| [swift-mutation-testing](https://github.com/ericodx/swift-mutation-testing) @ `e2ec75c` | MIT | yes | claimed | v1.4.0 |
| [MutantKit](https://github.com/juntaki/mutantkit) @ `3aca741` | Apache-2.0 | yes | listed as supported | v1.0.3 |
| [swift-mutants](https://github.com/P4suta/swift-mutants) @ `5594d5c` | MIT OR Apache-2.0 | yes | yes, needs Swift 6.3 and macOS 15 | unreleased |

- Muter runs the whole configured test command once per mutant and filters by
  coverage only whole files
  ([MutationTestingIODelegate.swift L166-176](https://github.com/muter-mutation-testing/muter/blob/7f1f2584e0a27fc05c952a5c8cdd52b10cc9513f/Sources/muterCore/MutationTesting/MutationTestingIODelegate.swift#L166-L176),
  [SwiftCoverage.swift L56-57](https://github.com/muter-mutation-testing/muter/blob/7f1f2584e0a27fc05c952a5c8cdd52b10cc9513f/Sources/muterCore/BuildSystems/Swift/SwiftCoverage.swift#L56-L57)),
  and its README warns that a mutated tree trips linters in the build — here
  SwiftLint rides inside the build (`Package.swift:12-14`).
- swift-mutants warns that tests reading source files fail under its
  instrumentation; 33 files under `Tests/` read source or other files as text
  (`grep -rln "packageRoot\|String(contentsOf" Tests`).
- **License posture.** The FSF lists Expat ("MIT") as "compatible with the GNU
  GPL" and Apache-2.0 as "compatible with version 3 of the GNU GPL"
  ([license list](https://www.gnu.org/licenses/license-list.html)). A tool that
  is run and not shipped is also covered by GPLv3 §2 ("You may make, run and
  propagate covered works that you do not convey, without conditions so long as
  your license otherwise remains in force") and §1,
  which excludes "general-purpose tools … used unmodified" from Corresponding
  Source ([GPLv3](https://www.gnu.org/licenses/gpl-3.0.txt), identical to this
  repository's `LICENSE`). None of these tools is a dependency of this
  repository, and adopting one is a dependency decision under AGENTS.md's
  license rule, not something this document proposes.
- **None of the sources read here describes a tool-free mutation protocol** for a reviewer: apply
  one mutation by hand, run, observe RED. The repository's own rule (§4.1) is
  that protocol, and where nothing can be run, a traced mutation is an argument,
  not a measurement.

---

## 4. How Slovo's own rules meet the above

### 4.1 "Tests must be able to fail" is a one-mutant kill requirement

`AGENTS.md:214-219` requires that every test "must be demonstrably able to go
red on broken code" and that each regression test document "the concrete
breakage" it catches. That is a requirement to kill at least one mutant (§3.1),
the note naming it. The notes are recorded as "Stated sensitivity: … → RED"
lines, which `.agents/rules/slop.md:60` protects from the prose review.

The rule governs a test's birth and nothing after it. It sets no bar on
redundancy, environment or price, and nothing removes a test once it exists.
The measured result, at `734435a`:

- 843 `@Test` lines in 149 files; 23,786 lines under `Tests/` against 12,902
  under `Sources/` (`find … -name "*.swift" | xargs cat | wc -l`);
- over the first-parent history of `Tests/`, 952 `@Test` lines added and 109
  removed; the initial commit `84a016a` added 172, and after it single commits
  added 68 (`2c084de`), 38 (`9559a79`, `b1c5543`) and 37 (`caa741b`,
  `2a2dee7`).

A sensitivity note states one mutant the test kills. It does not state whether
another test kills the same one (§2.3), whether the mutant is a behaviour change
or a behaviour-preserving edit (§2.2), or whether the test also fails on
something no mutant of the product touches (§2.1).

### 4.2 Source guards

Tests that read production source as text and assert on it: 25 files named
`*SourceGuard*` or `*GuardTests*` hold 420 `contains(` calls, and `contains("`
occurs 731 times across 58 test files. Two recorded reasons stand behind the
shape:

- **No behavioural seam into the app target.**
  `Tests/SlovoCoreTests/MenuBarGlyphWiringSourceGuardTests.swift:7` and
  `StatusItemPlacementSourceGuardTests.swift:7`: "`slovo` target is not
  importable, so these read its source". That is true of the manifest as written
  (§1.6: no test target depends on `slovo`) and not of SwiftPM, which has let a
  test target link an executable target since tools 5.5.
- **A deterministic substitute for a timing test.**
  `DictationHotPathLatencySourceGuardTests.swift:13-19` records that a
  wall-clock budget "was observed taking 0.24 s to 2.56 s on shared runners" and
  pins the absence of blocking primitives instead — the trade §2.1 recommends
  against sleeps and timing assertions.

By Eagle's definition (§2.2) a guard that asserts a transformation of the code
is a change-detector unless the text it pins is itself the contract. The
recorded reasons make that a question to answer per guard, not a verdict on the
shape.

### 4.3 Environment gates and shared state already in the suite

- `GrammarHintFindingsTests.swift:32-33,44` and
  `SpellCheckHintProviderIntegrationTests.swift:9-10,21` skip real
  `NSSpellChecker` and Text Input Sources tests whenever `CI` is set, with the
  reasons "real NSSpellChecker; skipped on shared CI" and, at
  `SpellCheckHintProviderIntegrationTests.swift:53`, "real Text Input Sources;
  skipped on shared CI" — the documented use of
  `.enabled(if:)` (§1.4). The trade is declared: CI never runs them.
- `KeychainKeySourceTests.swift:9-10` marks its suite `.serialized` because "the
  environment test mutates the process environment", and calls `setenv` and
  `unsetenv` at lines 18-23. By §1.2, `.serialized` does not order that suite
  against any other, and the environment block is shared by the process (§1.3).
  Whether another test reads the environment concurrently is the reviewer's
  question, not this document's.

### 4.4 The failure glyph test on macOS 27

`MenuBarGlyphImageTests.errorGlyphRendersAsNonTemplateRedImage`
(`Tests/SlovoCoreTests/MenuBarGlyphImageTests.swift:27-38`) requires every
pixel with alpha above 0.5 to classify as red (line 36). It passes on the
`macos-26` CI runner
([Release run 36270290486](https://github.com/Akurganow/slovo/actions/runs/36270290486)
at `734435a`: macOS 26.6.2, Xcode 26.6, Swift 6.3.3) and was reported failing
in a local `Scripts/diagnose.sh` run on Xcode 27, recorded in the body of pull
request [#109](https://github.com/Akurganow/slovo/pull/109) (merged as
`734435a`), which found it failing identically on `main` at `8aba13f` together
with `GrammarHintFindingsTests.realProviderReturnsGrammarFindingsWhenEnglishEnabled`;
that record does not state the macOS version, and no issue or CI run records
it. The
evidence read for this document does not establish a cause. What it
establishes:

- The drawing path is deprecated in macOS 27.0 —
  [`NSImage.lockFocus()`](https://developer.apple.com/documentation/appkit/nsimage/lockfocus()),
  `deprecatedAt: 27.0`:
  > This method is incompatible with resolution-independent drawing and should
  > not be used.
  No macOS 26, 26.1–26.6 or 27 release note mentions `NSImage`, `lockFocus`,
  `NSBitmapImageRep`, `NSColor` or system colours, or colour spaces; the only
  attributed-string drawing items (`NSStringDrawing`, macOS 26) concern natural
  alignment and paragraph-indentation direction. Their other image and text
  items concern menu-item images, `NSTextField` and TextKit 2 layout, SwiftUI
  `TextRenderer` and `AsyncImage` caching
  ([macOS 26](https://developer.apple.com/documentation/macos-release-notes/macos-26-release-notes),
  [macOS 27](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)).
- `NSColor.systemRed` is not one fixed value
  ([systemRed](https://developer.apple.com/documentation/appkit/nscolor/systemred)):
  > Returns a color object for red that automatically adapts to vibrancy and
  > accessibility settings.
  Of the four red values the
  [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/color)
  publish (light 255/56/60, dark 255/66/69, increased contrast light 233/21/45,
  increased contrast dark 255/97/101), only the last fails the test's
  classifier at full opacity (arithmetic on the published values).
- The failing test and three siblings in the same suite draw through the same
  `lockFocus` path, and Swift Testing runs them concurrently (§1.1); AppKit's
  [Thread Safety Summary](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/ThreadSafetySummary/ThreadSafetySummary.html)
  states "The underlying image cache is shared among all threads."
- The GitHub-hosted `macos-26` image runs macOS 26.6.2 with Xcode 26.6; macOS 27
  is available only as the preview image labelled `xcode-27`
  ([macos-26-arm64-Readme.md](https://raw.githubusercontent.com/actions/runner-images/ede07f8e48022b2c00dc669c7a9d927c46e32a81/images/macos/macos-26-arm64-Readme.md),
  [xcode-27-arm64-Readme.md](https://raw.githubusercontent.com/actions/runner-images/ede07f8e48022b2c00dc669c7a9d927c46e32a81/images/macos/xcode-27-arm64-Readme.md)).
  Both images set only `reduceMotion` and `reduceTransparency`; neither sets
  dark mode, increased contrast or font smoothing
  (`images/macos/scripts/build/configure-system.sh:19-21` at `ede07f8`).

Telling these apart takes one run on macOS 27 that prints the decoded bitmap's
format and colour space, the resolved `systemRed`, and each opaque pixel that
fails the classifier, alone and in the full suite. No such run was made here.

---

## 5. The criteria a review applies

Each kind is a way a test that **can** fail costs more than it protects. A test
that cannot fail at all is `ceremony` in `.agents/rules/slop.md:40` and is not
repeated here. Each criterion names the exhibit that proves it; where nothing
can be run, the exhibit is a traced argument and the conclusion is plausible,
never confirmed. The repository adopts these criteria in
`.agents/rules/tests.md`, which is authoritative; this table records the
sources behind each.

| Kind | The test | The exhibit | Recorded exceptions | Sources |
| :-- | :-- | :-- | :-- | :-- |
| environment-coupled | The outcome depends on an input the test does not control: the OS or toolchain, a renderer, a system service, locale, the clock, scheduling, or process-global state other tests can touch | The uncontrolled input, traced to the assertion, and two environments (or two schedules) under which it differs, each documented or observed | A real platform facility exercised on purpose and gated with a stated reason; the finding is then whether the gate hides the only signal. Before blaming the test, show the nondeterminism is not the product's | §1.2-1.4, §2.1 (Parry Table 4, Luo, Meszaros Context Sensitivity, Fowler) |
| change-detector | It pins implementation text or structure where a behaviour or the compiler already guards the contract | A behaviour-preserving edit, written out, that turns it red; and the behaviour test or compiler check that already guards the contract | The how is the requirement (a cache read, a call count or order that has side effects); no behavioural seam exists, recorded | §2.2 (Eagle, SWE ch. 12, Trenk, Beck) |
| redundant | Every mutant it kills, another test kills | The mutants its note and body imply, each with the other test that goes red on it | Deliberate redundancy with a recorded reason; a regression input distinct from what the other test feeds | §2.3, §3.1 (van Deursen, Meszaros, Shi et al., Ammann et al.) |
| over-specified | The assertion demands more than the requirement: exact where the requirement is a property, a tolerance or a range | The requirement quoted, and an output that meets it and fails the assertion | Exactness that is the requirement: a byte-exact wire format, a prompt sent verbatim | §2.4 (Meszaros, Kent, Parry Too Restrictive Range, Dawson) |
| disproportionate | Its machinery (a rendered pixel, parsed source text, the wall clock, a real system service) is heavier than the contract it guards, and a cheaper point in the app already makes the decision it checks — so the extra weight checks the platform | The contract in one sentence, quoted; the decision's line; the smallest test that guards it, written out, caught by the same mutation of that decision; and the ways the current test fails with no change to the app | The one designated test of a platform seam, named as such; a visual result that is itself the requirement; a platform behaviour that has broken the product before, on record | §2.6 (SWE ch. 11 and 13, Beck, JUnit FAQ, Meszaros and Feathers, WWDC18 417, HIG, Android, Vocke) |
| bloat | A file or cluster grew without a matching contract: more tests, lines or helpers than the contracts they pin | Both columns measured: the cost (tests, lines, edits in commits that changed no behaviour) and the protection only these tests provide | Duplication kept for clarity (DAMP); a merge that would hurt readability | §2.5 (SWE ch. 11-12, Meszaros, Luo, Picard) |

Two rules hold across the kinds:

- **No protection is lost silently.** A removal names, for each mutant the test
  kills, the test that still kills it. What no other test kills is either kept
  or replaced, never dropped (Meszaros's Lost Test; Luo's "should not simply be
  removed"; Shi et al.'s mutant-based reduction).
- **A rewrite must not create the opposite smell.** A test written only to kill
  a mutant can pin the current implementation (Petrović et al., §2.2).

Tests born with a fix are a sweep, not a kind: each is judged by the kinds above
against what later commits did to the code it pins (§2.7). "It never failed" is
never grounds on its own (Memon et al.).

---

## Full sources

Swift Testing and SwiftPM
- https://developer.apple.com/documentation/testing and its articles
  `parallelization`, `migratingfromxctest`, `organizingtests`,
  `enablinganddisabling`, `known-issues`, `exit-testing`, `testscoping`,
  `trait/serialized`, `test/cancel(_:sourcelocation:)` (read as DocC JSON)
- https://github.com/swiftlang/swift-testing @ `ea850751b69a18e332619feab7777ebc54f39c62`,
  tags `swift-6.3.3-RELEASE`, `swift-6.4.0-RELEASE`
- https://github.com/swiftlang/swift-evolution @ `d7b4e0ad0946bc34d475130aae0fe6edaa77f867`
  (ST-0003, ST-0007, ST-0008, ST-0026)
- https://developer.apple.com/videos/play/wwdc2024/10179/ (Meet Swift Testing)
- https://developer.apple.com/videos/play/wwdc2024/10195/ (Go further with Swift Testing)
- https://forums.swift.org/t/81251 (maintainers' posts; not normative)
- https://raw.githubusercontent.com/swiftlang/swift-package-manager/main/CHANGELOG.md

Testing literature
- Micco 2016, Eagle 2015, Trenk 2013 (two posts), Kent 2024, Picard 2008 —
  testing.googleblog.com, URLs inline
- Luo, Hariri, Eloussi, Marinov, FSE 2014 —
  http://mir.cs.illinois.edu/marinov/publications/LuoETAL14FlakyTestsAnalysis.pdf
- Parry, Kapfhammer, Hilton, McMinn, ACM TOSEM 31(1) 2022 —
  https://eprints.whiterose.ac.uk/id/eprint/230095/1/parry2021.pdf
- Fowler 2011 — https://martinfowler.com/articles/nonDeterminism.html
- Software Engineering at Google, chs. 11, 12, 14 —
  https://abseil.io/resources/swe-book/html/
- van Deursen, Moonen, van den Bergh, Kok, XP 2001 — https://ir.cwi.nl/pub/4324/04324D.pdf
- Meszaros, xUnit Test Patterns (web draft) — http://xunitpatterns.com/
- Beck, Test Desiderata — https://testdesiderata.com/
- Shi, Gyori, Gligoric, Zaytsev, Marinov, FSE 2014 —
  http://mir.cs.illinois.edu/marinov/publications/ShiETAL14ReductionEvolution.pdf
- Dawson 2012 — https://randomascii.wordpress.com/2012/02/25/comparing-floating-point-numbers-2012-edition/

Proportion and the life of a regression test
- Software Engineering at Google, ch. 13 —
  https://abseil.io/resources/swe-book/html/ch13.html
- JUnit 4 FAQ — https://junit.org/junit4/faq.html
- Meszaros, Humble Object — http://xunitpatterns.com/Humble%20Object.html;
  Feathers, The Humble Dialog Box (2002) —
  https://martinfowler.com/articles/images/humble-dialog-box/TheHumbleDialogBox.pdf
- WWDC18 417, Testing Tips & Tricks — https://developer.apple.com/videos/play/wwdc2018/417/
- Human Interface Guidelines, Color —
  https://developer.apple.com/design/human-interface-guidelines/color
- Android Developers, Screenshot testing —
  https://developer.android.com/training/testing/ui-tests/screenshot
- Vocke, The Practical Test Pyramid (2018) —
  https://martinfowler.com/articles/practical-test-pyramid.html
- Pinto, Sinha, Orso, FSE 2012 (abstract) — https://doi.org/10.1145/2393596.2393634
- Beck, Composable Tests (2025) — https://newsletter.kentbeck.com/p/composable-tests
- Memon et al., ICSE-SEIP 2017 — https://research.google.com/pubs/archive/45861.pdf

Mutation analysis
- Jia & Harman, IEEE TSE 2011 — http://crest.cs.ucl.ac.uk/fileadmin/crest/sebasepaper/JiaH10.pdf
- Ammann, Delamaro, Offutt, ICST 2014 —
  https://www.albany.edu/faculty/offutt/research/papers/MiniMutant-ICST2014.pdf
- Petrović & Ivanković, ICSE-SEIP 2018 —
  https://storage.googleapis.com/gweb-research2023-media/pubtools/4203.pdf
- Petrović, Ivanković, Fraser, Just — https://arxiv.org/pdf/2102.11378,
  https://arxiv.org/pdf/2103.07189
- The tools in §3.3 at the commits named; FSF license list and GPLv3 text at
  gnu.org

Platform facts for §4.4
- AppKit `NSImage.lockFocus()`, `NSColor.systemRed`, macOS 26 and 27 release
  notes (DocC JSON); Human Interface Guidelines, Color; AppKit Thread Safety
  Summary; actions/runner-images @ `ede07f8e48022b2c00dc669c7a9d927c46e32a81`

---

## Verification

Date: 2026-09-26
Verdict: **PARTIAL → fixed** — every correction below is applied in this file.

Independent verification of every quoted passage, every repository figure and
every platform fact against the live sources; the verifier did not write this
document. Apple pages were read through their DocC JSON, the HIG through its
design JSON, WWDC24 transcripts from the video pages, GitHub sources from clones
at the named commits, PDFs by text extraction. Repository figures were
re-derived at `734435a`; the release bump `a5b15b5` that followed it on `main`
touches only `CHANGELOG.md` and `Resources/Info.plist`, so they hold there too.
123 claims checked: 109 OK, 6 wrong, 8 unsupported, 0 unreachable.

### Confirmed against a primary source

- **All quotations are verbatim** (Apple DocC articles and symbol pages, WWDC24
  10179/10195, ST-0003/ST-0007/ST-0026, swift-testing sources at `ea85075` and
  `swift-6.3.3-RELEASE`, the t/81251 posts, the SwiftPM CHANGELOG, Google Testing
  Blog posts, SWE book chs. 11/12/14, xUnit Patterns, Fowler, Beck, Dawson, and
  the nine papers). Only typographic differences exist, plus the dropped
  citation "[38]" in Shi et al. and the sources' own typos "asynchonous"
  (Fowler) and "to removed" (Meszaros).
- **Versions:** `TestScoping` Swift 6.1 / Xcode 16.3; exit tests 6.2 / 26.0;
  `Test.cancel` 6.3 / 26.4 (public at 6.3.3); `.taskLocal` Swift 6.5, on `main`
  only; `.serialized(for:)` `@_spi(Experimental)` at 6.4.0 and `main`, 0
  occurrences at 6.3.3; XCTest interop defaults to `none` below toolchain 6.4.
- **Tools:** Muter `7f1f258` MIT, `--skip-build` per mutant, whole-file coverage
  filter, tag `16` of 2023-09-16 is what the Homebrew tap installs;
  swift-mutation-testing `e2ec75c` MIT v1.4.0; MutantKit `3aca741` Apache-2.0
  v1.0.3; swift-mutants `5594d5c` MIT OR Apache-2.0, unreleased. FSF lists Expat
  and Apache-2.0 as GPL(v3)-compatible; gnu.org's `gpl-3.0.txt` and this
  repository's `LICENSE` have the same MD5 (`1ebbd3e34237af26da5dc08a4e440464`).
- **Glyph test:** passes on `macos-26` in Release run 36270290486 at `734435a`
  (macOS 26.6.2, Xcode 26.6, Swift 6.3.3). With the test's classifier, of the
  HIG reds only increased-contrast dark fails (g = 0.380, b = 0.396).
  `lockFocus()` carries `deprecatedAt: 27.0`. Both runner images set only
  `reduceMotion` and `reduceTransparency`.

### Corrections (before → after)

1. §4.1 line counts: 23,688 / 12,903 → 23,786 / 12,902 (the old figures were
   the parent commit's).
2. §4.1 history: the initial commit `84a016a` (172 `@Test` lines) named before
   the largest later commits.
3. §4.2 counts: 417 / 728 → 420 / 731.
4. §4.3: the Text Input Sources test's own skip reason quoted.
5. §2.5: "no Google Testing Blog post on deleting tests was found" → Picard,
   *Cost-Benefit Analysis of a Test* (2008), quoted.
6. §3.3 Muter: tag `16` matches XCTest's, xcodebuild's and Buck's failure lines
   and scores any other non-zero exit as a kill, not "XCTest output only".
7. §3.3: "No source describes…" → "None of the sources read here describes…".
8. §1.1: the dictionary (`Graph.swift` L30) and the `Hasher` seed cited; the
   6.3.3 lines are L310-312.
9. §1.2 table: "it still runs concurrently" → "it may still run concurrently".
10. §4.4: the `macos-26` pass cited to its run; the macOS 27 failure marked as a
    report from outside the repository.
11. §4.4: the release-note sentence narrowed to what the notes do and do not
    mention; the macOS 26 notes linked.
12. §4.4: "`systemRed` is resolved against the current appearance" → "is not one
    fixed value".
13. §4.4: runner versions cited to the image readmes at `ede07f8`.
14. Full sources: "Listfield 2017", cited nowhere, removed.

### Could not be reached directly

- gnu.org over HTTPS: `curl: (35) Recv failure: Connection reset by peer`; over
  HTTP it answered 503 four times, then 200.
- github.com HTML pages answered 403; the same files were read from clones and
  raw.githubusercontent.com at the same commits.

### Only confirmable on a real macOS 27 machine

1. Why `errorGlyphRendersAsNonTemplateRedImage` fails there: a different resolved
   `systemRed`, a changed bitmap format or colour space from
   `tiffRepresentation`, or concurrent `lockFocus` drawing across the four
   sibling tests. One run on macOS 27 printing the decoded bitmap's format and
   colour space, the resolved `systemRed` components and each opaque pixel that
   fails the classifier — alone and in the full suite — settles it.
2. Whether the failure reproduces on the GitHub `xcode-27` preview image.

### Second pass

Verdict: **PARTIAL → fixed**, every correction below applied in this file. An
independent verifier re-checked every line added after the first pass against
live sources: each quoted passage verbatim, with its attribution and the
sentence it supports, every added factual sentence, and the first pass's
corrections. Every quote in §2.5–2.7 held (Picard 2008; SWE chs. 11, 12, 13;
Beck, Test Desiderata and Composable Tests; JUnit 4 FAQ; Meszaros, Humble
Object; Feathers 2002; WWDC18 417; HIG Color; Android Screenshot testing;
Vocke 2018; Pinto et al. FSE 2012, abstract through OpenAlex and Crossref; Memon
et al. ICSE-SEIP 2017), as did the `Hasher` quote and the extended GPLv3 §2 quote
(`LICENSE:164-166`). The repository figures were re-derived at `734435a` from an
archive of that commit and held.

Corrections (before → after):

- §1.5: `MigratingFromXCTest.md L43-45` → `L44-46`.
- §2.7: "Google's answer was to run such tests less often, not to delete them" →
  the paper proposes running them less often and does not propose deleting them.
- §2.7: "by deletion and addition" → "by refactoring, deletion and addition",
  as the quoted abstract says.
- §4.4: "a report from outside the repository" → the report is in the body of
  pull request #109 (merged as `734435a`): a local `Scripts/diagnose.sh` run on
  Xcode 27, failing identically on `main` at `8aba13f` together with
  `GrammarHintFindingsTests.realProviderReturnsGrammarFindingsWhenEnglishEnabled`;
  it names no macOS version, and no issue or CI run records it.
- §4.4: the macOS 26 release notes do mention `NSStringDrawing`, for natural
  alignment and indentation direction; the negative is scoped to `NSImage`,
  `lockFocus`, `NSBitmapImageRep`, `NSColor` and system colours, and colour
  spaces, and `AsyncImage` caching joins the list of image items.
- §3.3: Muter's tag 16 scores a non-zero exit as a runtime error only when its
  log shows no build error.
- §5: the `disproportionate` sources add Android and SWE ch. 13; the `bloat`
  sources add Picard.

Could not be reached directly: www.gnu.org reset the connection twice (the
GPLv3 text was matched against the repository's `LICENSE` and the SPDX copy);
doi.org and dl.acm.org answered 403 (Pinto et al.'s metadata and abstract came
from Crossref and OpenAlex; the full text is closed access).
