---
kind: dismissal
departments:
  - tests
issue: 160
date: 2026-11-26
finding: Tests/SlovoCoreTests::private-test-doubles::bloat
---

The finding is dismissed.

Issue: https://github.com/Akurganow/slovo/issues/160

Title of the lead:
~~~
[Test Police] bloat: Tests/SlovoCoreTests — 346 lines of private test doubles implement seven mechanisms two to four times each
~~~

The comment of the decider who closed the lead, written 2026-11-26T21:18:32Z:
~~~
Moved into #159, re-measured on `main` at f0a74d1: both issues move private orchestrator test machinery into shared test support, share four files, and are one change. What still holds and what became void are listed there.
~~~
