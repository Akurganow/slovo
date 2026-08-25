# Task brief — key-scoped cleanup models, and a catalog refresh

Status: **formulated, not started.** This file states the problem, the
requirements, and what must be researched. It does not choose an implementation.

## 1. What the user sees today

Slovo ships a fixed list of seven cleanup models. Any OpenRouter key unlocks the
whole list, because the list is a hard-coded constant and nothing ever asks the
key what it is allowed to call.

OpenRouter keys are not interchangeable. A key issued by a company, a team, or an
org can be narrower than a personal one: models switched off by policy, providers
excluded, no credits for the paid tier. With such a key the user picks a model
Slovo offered them, and then every dictation fails the same silent way:

- the request comes back 4xx, `OpenRouterCleaner` maps it to `CleanupError.apiError`;
- the raw transcript is inserted instead of the cleaned one (product intent, step 5);
- the failure glyph flashes, the Error cue plays;
- nothing anywhere says *which* choice caused it — and by house rule nothing may
  open a dialog to say so.

The user has no way to tell a wrong model from a dead network. They rediscover it
one dictation at a time.

Second, smaller problem: the seven ids are hand-maintained and were chosen once.
Model availability, price, and latency on OpenRouter move fast, and a retired id
fails exactly like a forbidden one.

## 2. Two sub-tasks, one seam

**A. Key-scoped availability** — offer only models the *saved key* can actually
call. This is the correctness problem and the reason for the task.

**B. Catalog refresh** — a market pass over the fast-cleanup tier, benchmarked,
so the shortlist reflects what exists now.

They share one seam (`CleanupModelCatalog`), so they belong in one brief. B must
not block A.

## 3. What must be true when it is done

- The Settings picker and the menu-bar dropdown offer the same set, and that set
  contains nothing the current key cannot call.
- The free-form custom-model field keeps working. A custom id outside the key's
  scope should be answerable *before* the next dictation fails, not after.
- **Fail open, never closed.** If the key's scope cannot be established — offline,
  endpoint error, the API simply does not expose it — the full curated list is
  shown. An empty picker is a worse failure than an optimistic one.
- **Nothing new on the key-up path.** Cleanup already sits on the latency-critical
  step. Scope is established when a key is saved / on app start / when Settings
  opens, cached, and never fetched during a dictation.
- A saved model that turns out to be uncallable needs one defined, visible-at-a-
  glance behavior. Note the asymmetry with the existing retired-id migration in
  `ConfigStore.load`: "retired" is a static fact about the world, "not in your
  key's scope" is per-key and reversible — so silently rewriting the stored choice
  is probably wrong here. Decide deliberately.
- Errors stay non-focus-stealing: status lines and glyphs only, no alerts.
- Privacy posture unchanged: the scope lookup carries the key to OpenRouter and
  nothing else. No transcript, no new egress.
- Data-driven attractor: one piece of state (curated catalog + fetched key scope),
  both pickers as projections of it. Not two lists kept in sync by hand.

## 4. What has to be researched first (evidence, not assumption)

Nothing below is verified yet. Read the official OpenRouter docs before designing.

1. **Is key scope visible through the API at all?** Candidates to check:
   `GET /api/v1/models` (does it honor an `Authorization` header and return a
   key-scoped subset?), `GET /api/v1/key` (what key metadata is exposed — limits,
   provisioning flag, any allowed-model field), org/provisioning-key semantics,
   and any documented per-key model restriction. The answer decides the whole
   design.
2. **If it is not visible**, the fallback is error-shaped: distinguish the 4xx
   codes the cleaner already receives (invalid key vs. model not permitted vs.
   no credits vs. unknown model) and turn the first failure into a durable,
   user-visible fact instead of a repeated silent one. `CleanupError.apiError`
   already carries the status, so the raw material is there.
3. **Corporate specifics**: org-level model policies, zero-data-retention
   settings filtering providers out, BYOK/provider keys — do any of them change
   the callable set per key, and are they reported anywhere?
4. **Market pass for the cleanup tier.** The step is a constrained rewrite at
   temperature 0 with `reasoning: {effort: "none"}`, on the key-up critical path.
   What is current in the fast/cheap tier, how does it handle RU+EN
   code-switching, what has been retired since the list was written. Also worth
   checking: OpenRouter routing knobs (provider preference/sorting, throughput or
   price shortcuts, an ordered fallback `models` array) — a fallback list might
   solve part of problem A for free.
5. **Are any of the seven current ids already stale?** Verify each against the
   live catalog; retire through the existing migration mechanism.

## 5. Ground already covered — do not rediscover it

| Thing | Where |
| --- | --- |
| The list itself | `Sources/SlovoCore/Cleaner/CleanupModelCatalog.swift`; default id in `Config.defaultOpenRouterModel` |
| Consumers | `Sources/slovo/Settings/CleanupSettingsPane.swift` (picker + custom id), `Sources/slovo/AppDelegate+CleanupMenu.swift`, `Sources/slovo/DictationMenuBuilder.swift` |
| Source guards asserting those consumers read the catalog | `Tests/SlovoCoreTests/SettingsSurfaceSourceGuardTests.swift`, `AppRuntimeSourceGuardTests.swift`, `AppShellPackagingTests.swift` — a redesign must update them deliberately, not incidentally |
| Retired-id migration | `ConfigStore.load`, covered by `Tests/SlovoCoreTests/ConfigStoreCatalogMigrationTests.swift` |
| Single source of truth for cleanup on/off/no-key | `CleanupAvailability` + `CleanupAvailabilityModel` (one writer, the app's push funnel). Key-scope state should ride this funnel or an analogous single writer — not a second parallel path |
| Request and failure mapping | `Sources/SlovoCore/Cleaner/OpenRouterCleaner.swift`, `OpenRouterRequest.swift`; `CleanupError.{missingKey, offline, rateLimited, apiError(status:)}` |
| Benchmark for part B | `slovo-cleanup-benchmark` + `Benchmarks/cleanup/slovo-cleanup-v1.json` (50 samples, 7 categories); usage in `docs/references/cleanup-benchmark.md`. Pass rate and p50/p95 from this harness are the evidence a catalog change stands on |

## 6. Cynefin gate

- **Clear** — swapping model ids in the catalog and re-running the benchmark:
  verify live, one call per model, no RED→GREEN ceremony.
- **Complicated** — scope discovery, caching, fail-open behavior, and the picker
  projection: full RED→GREEN, with the mutation each regression test catches
  written down.

## 7. Open decisions for the owner

- Keep a curated shortlist intersected with the key's callable set (recommended —
  the full OpenRouter catalog is thousands of models and nearly all are wrong for
  this step), or show the key's callable list directly?
- Auto-switch away from a model the key cannot call, or leave the choice standing
  and mark it unavailable?
- Is a "your key cannot use this model" status line under the picker wanted? It
  fits the existing status-line pattern and breaks no house rule.
