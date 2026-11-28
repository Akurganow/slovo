---
kind: dismissal
departments:
  - agent-config
issue: 167
date: 2026-11-26
finding: .agents/skills/abstraction-police/SKILL.md::duplicated-proof::role-contradicts-rule
---

The finding is dismissed.

Issue: https://github.com/Akurganow/slovo/issues/167

Title of the lead:
~~~
[Agent Police] role-contradicts-rule: .agents/skills/abstraction-police/SKILL.md — the duplicated kind prescribes no measurement for "one concept", so look-alikes reach the court
~~~

The comment of the decider who closed the lead, written 2026-11-26T21:18:44Z:
~~~
Obsolete: the file this issue targets, `.agents/skills/abstraction-police/SKILL.md`, no longer exists, and neither does `.agents/skills/`. c36de4e (#183) and 04a5ab4 (#184) retired the police roles together with `.agents/rules/police.md` and `.agents/adaptation.md`, which this issue also cites. No rule file defines a `duplicated` kind any more, so the proposed bullet has no home.
~~~
