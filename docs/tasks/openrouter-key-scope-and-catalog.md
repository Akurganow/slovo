# Spec 2026-08-26 — key-scoped cleanup models

Status: **spec, approved directions; implementation not started.** This file
began as the task brief; the research it called for is done (live verification
2026-08-26, two-key run: personal unrestricted + corporate restricted with an
exhausted org budget) and the owner has decided the open questions. Part B (the
market refresh of the catalog itself) remains a separate, benchmark-driven
change — see §8.

## 1. Problem

Slovo ships a curated list of seven cleanup models, and any OpenRouter key
unlocks the whole list, because nothing ever asks the key what it may call.
Corporate keys are narrower by policy (org guardrails carry model allowlists).
With such a key the user picks a model Slovo itself offered, and every
dictation then fails the same silent way: HTTP 404 → `CleanupError.apiError` →
raw transcript inserted, failure glyph, Error cue — nothing says *which choice*
caused it, and house rules forbid a dialog that could. A wrong model is
indistinguishable from a dead network, one dictation at a time.

## 2. Verified facts (live run 2026-08-26; primary-source docs)

| Fact | Evidence |
| --- | --- |
| `GET /api/v1/models/user` returns the models THIS key can call; requires auth (401 bare); free — zero credits consumed | 200 with both keys; corp usage bit-identical before/after |
| Filtering is real and per-key: corp list is a strict subset (219 vs 414); the two catalog ids the org disabled are exactly the ones missing | live diff |
| Even a personal key's `/models/user` is filtered (417 → 414) — filtering is not only org policy | live |
| Schema matches `/models` minus `benchmarks`; only `data[].id` is needed | live |
| `/models` is identical with/without/any auth — useless for scoping | live |
| Runtime error map: **400** invalid model id · **401** dead key · **403** org budget exhausted *and also* (per docs) moderation-flagged input — ambiguous by status · **404** blocked by guardrail/data policy · **429** rate limit | live probes P1–P3 + official error docs |
| Budget exhaustion is 403 (docs say 402 — wrong) and `GET /key` shows `limit`/`limit_remaining = null` for the corp key: **an exhausted org budget is invisible to metadata** — no pre-flight credit check exists | live |
| Error bodies can carry `user_id` — an account identity string. Never log response bodies verbatim | live P1 |
| All 7 current catalog ids exist in `/models` — the catalog is not stale | live |

## 3. Decisions (owner, 2026-08-26)

- **D1 Pickers hide unavailable models**: both pickers show curated catalog ∩
  key scope. Nothing greyed-out, no browsing the key's full list.
- **D2 The stored choice is never rewritten**: the *effective* model is derived
  (same idiom as `CleanupAvailability.derive` — preference preserved, effect
  computed). Switching back to a wider key revives the old choice by itself.
- **D3 Custom id outside the scope: accept and warn** — a caption under the
  field, no hard block (the cache may be stale or absent; fail open).
- **D4 Scope cache is in-memory only**: fetched per launch / per key save,
  nothing persisted, nothing to migrate or invalidate across restarts.

## 4. Design

### State

One new piece of state in the app funnel, beside cleanup availability:

```
CleanupModelScope = .unknown | .known(Set<String>)   // ids from /models/user
```

`.unknown` covers: no fetch yet, no key, fetch failed (offline / non-200 /
decode). It is indistinguishable from "everything allowed" by design — fail
open (K5).

### Invariants

- **K1** The stored `Config.openRouterModel` is never rewritten by scope logic.
  (The existing retired-id migration in `ConfigStore.load` is untouched —
  "retired from the world" stays a load-time migration; "not in this key's
  scope" is runtime derivation.)
- **K2** One pure derivation, one call site per surface:
  `derive(preference, catalog, scope) → (options, effectiveModel, note?)`.
  - scope `.unknown` → options = full catalog, effective = preference, no note.
  - preference ∈ scope → effective = preference.
  - preference is a CATALOG id ∉ scope → effective = the catalog default if in
    scope, else the first catalog option in scope; note names the substitution.
    If NO catalog option is in scope → effective = preference (fail open; the
    failure then surfaces genuinely, K9).
  - preference is a CUSTOM id ∉ scope → **effective = preference**, note warns.
    Rationale for the asymmetry: a catalog choice was made from a list WE
    offered, possibly under a different key — substituting repairs our own
    stale offer. A custom id is the user's explicit assertion (D3 already
    warned them); overriding it would violate intent primacy. It fails
    genuinely at runtime if truly blocked, which also triggers K4d.
- **K3** Both pickers render `options` from K2 — the Settings picker and the
  menu-bar submenu are projections of the same derivation (shared options
  source, as today via `CleanupModelCatalog`). The Settings picker's selection
  displays the EFFECTIVE model; a stored non-catalog custom id keeps its extra
  row (current behavior) and stays selectable. When effective ≠ preference,
  the note is the caption under the picker — the existing status-line pattern,
  no new UI vocabulary.
- **K4** Scope is (re)fetched only at: (a) app launch with a key present,
  (b) key save, (c) key removal → reset to `.unknown`, (d) a cleanup failure
  with status 404 → invalidate and refetch in the background (the policy
  changed under our cache; one trigger, no polling). NEVER on the key-up path:
  a dictation reads the already-derived effective model.
- **K5** Fail open. `.unknown` must produce today's exact behavior: full
  catalog, preference used verbatim, zero captions. An empty picker is a
  worse failure than an optimistic one.
- **K6** Single writer: the same app-layer push funnel that writes
  `CleanupAvailabilityModel` (spec D1 there) writes the scope's observable
  model. Views and the pipeline consume projections; no second mutation path.
- **K7** The fetch is `GET https://openrouter.ai/api/v1/models/user` with the
  Keychain key as Bearer; parse `data[].id` only. Logging stays
  redaction-safe events ("scope fetched n=…", "scope fetch failed: offline");
  response bodies are never logged (they can carry `user_id` — §2).
- **K8** Cleanup-time error handling is behaviorally unchanged (failure → raw
  insert, glyph, cue). Two additions only: status 404 triggers K4d, and no
  message-text parsing anywhere (403 is ambiguous by status — budget vs
  moderation — and text is not a contract).
- **K9** No persistence (D4). No pre-flight budget check (§2: impossible).
  Translation rides the same single cleanup step — the effective model applies
  to it automatically; nothing translate-specific.

### Components

- **SlovoCore**: `CleanupModelScope` value; the K2 derivation (pure,
  `CleanupModelCatalog`-adjacent); `OpenRouterModelScopeFetcher` (URLSession +
  `OpenRouterKeyProvider` → `Set<String>`, same seam style as
  `OpenRouterCleaner`).
- **App layer**: an observable scope holder written by the availability funnel
  (mirroring `CleanupAvailabilityModel`); `CleanupSettingsPane` and
  `AppDelegate+CleanupMenu` switch from `CleanupModelCatalog.options` to the
  K2 projection; the caption strings live with the pane.
- **Pipeline**: the effective model (not the raw preference) flows into
  `CleanupConfig.model` where the config snapshot is built, once per dictation.

## 5. Non-goals

- No pre-flight credit/budget checks (proven impossible for org budgets).
- No browsing of the key's full model list; the catalog stays curated.
- No persisted scope, no TTL/refresh timers beyond K4's four triggers.
- No parsing of error message text; no new error UI beyond existing patterns.

## 6. Verification plan (Cynefin-gated)

**Complicated — full RED→GREEN, each test's breakage documented:**
- K2 derivation: every branch, plus mutation sensitivity (e.g. swap the
  custom/catalog asymmetry → RED; make substitution rewrite the preference →
  RED via a preference-unchanged assertion).
- K5: fetch failure ⇒ options == full catalog and effective == preference
  (mutate fail-open to fail-closed → RED).
- K4d: a 404 cleanup failure invalidates and refetches; 403/offline do not.
- K6/K3: update the source guards deliberately —
  `SettingsSurfaceSourceGuardTests`, `AppRuntimeSourceGuardTests`,
  `AppShellPackagingTests` currently assert both surfaces read
  `CleanupModelCatalog`; they must assert the K2 projection instead.
- K7: fetcher never logs bodies (source guard on the fetcher file).

**Clear — direct verification, no ceremony:**
- Request shape of the fetcher: one live call per key kind (already evidenced
  by the 2026-08-26 run; re-verify once against the built fetcher).

Full gates before integration: `Scripts/diagnose.sh`; owner hand-check via
`SIGNING_IDENTITY=… Scripts/build_and_run.sh --verify` per the standing
directives.

## 7. Behavior walk-through (the owner's two keys)

- Personal key: scope = 414 ids ⊇ catalog → pickers unchanged, no captions,
  behavior byte-identical to today.
- Corporate key: pickers show 5 of 7 (Claude Haiku 4.5 and Qwen3.6 Flash
  hidden). If the stored choice was Claude Haiku 4.5 → cleanup silently uses
  the default (GPT-5.6 Luna); Settings shows the substitution caption. Budget
  is exhausted, so cleanup still fails 403 → raw text inserted with glyph+cue,
  as product intent dictates — but no longer *because of a model we offered
  and shouldn't have*.
- Key removed: scope `.unknown`, cleanup offNoKey — untouched existing path.

## 8. Part B — catalog refresh (pending, separate change)

All seven ids are alive (§2), so nothing is on fire. A market pass over the
fast-cleanup tier stays queued: candidates in, `slovo-cleanup-benchmark`
(50 samples × repetitions, pass rate + p50/p95) decides, catalog + retired-id
migration updated in the winning change. Not blocked by, and not blocking,
this spec.
