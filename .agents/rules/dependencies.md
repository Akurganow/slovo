# Dependencies: the promises an update must keep

Facts of this repository that a dependency update is checked against. Its
readers are whoever reviews or applies one. The update bot is
`dependabot[bot]`. It watches the `github-actions` and `swift` ecosystems
(`.github/dependabot.yml`).

## Promises an update must not break

- the decisions the comments in `Package.swift` and `.github/dependabot.yml`
  record;
- the app's floor in the `platforms:` of `Package.swift`;
- the target split, under which the core stays free of the app shell and the
  update engine (`docs/architecture.md`, "Build Boundaries");
- the licence posture: a GPLv3-compatible licence, with
  `THIRD-PARTY-NOTICES.md` and the licence section of `README.md` kept
  current (`AGENTS.md`, "Non-negotiable principles" and "License compliance
  is part of every change").

## A quality-gated dependency

`argmax-oss-swift`, the speech-recognition engine, is never safe to merge
from reading alone. An update needs a review of recognition quality on real
hardware before merge (`.github/dependabot.yml`; `AGENTS.md`,
"Non-negotiable principles", 6).

## Advisories

The packages in `Package.resolved`, the actions the workflows under
`.github/workflows/` use, and tools pinned inside a workflow outside the
bot's reach are all dependencies. An advisory is resolved by the update
command, never by a hand edit of `Package.resolved`.

This file describes `Package.swift`, `.github/dependabot.yml` and the
workflows. Where they disagree with it, they win and this file is stale.
