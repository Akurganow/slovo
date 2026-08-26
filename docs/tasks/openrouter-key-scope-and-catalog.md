# Spec 2026-08-26 rev 3 — key-scoped cleanup models

Status: **spec, approved directions; implementation not started.** Rev 2
incorporated the first independent adversarial review (verdict REWORK on
rev 1); the two judgment calls it introduced were decided by the owner (§9).
Rev 3 incorporates a second independent review of rev 2 (verdict APPROVE WITH
CHANGES): fetch generations replace the ambiguous coalescing rule (K4), the
transition logic moves into a testable SlovoCore reducer (K11), and the K2/K3
edge cases it caught are closed. No owner decision is reopened. The research phase is done (live
two-key verification 2026-08-26: personal unrestricted + corporate restricted
with an exhausted org budget). Part B (the market refresh of the catalog
itself) remains a separate, benchmark-driven change — see §8.

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
  custom-id field, no hard block (the cache may be stale or absent; fail open).
- **D4 Scope cache is in-memory only**: fetched per launch / per key save,
  nothing persisted, nothing to migrate or invalidate across restarts.

## 4. Design

### State

One new piece of state in the app funnel, beside cleanup availability:

```
CleanupModelScope = .unknown | .known(Set<String>)   // ids from /models/user
```

`.unknown` covers: no fetch yet, no key, cleanup effectively off, fetch failed
(offline / non-200 / decode). Fail open (K5).

### K2 — one pure derivation

`derive(preference, catalog, scope) → (options, effectiveModel, note?)`,
defined on the FULL input space; both pickers and the pipeline consume only
its output. `catalog` is `CleanupModelCatalog.options` in declaration order;
"first available" always means that order.

| scope | preference | options | effective | note |
| --- | --- | --- | --- | --- |
| `.unknown` | any | full catalog (+ custom row when preference ∉ catalog, K3) | preference | none |
| `.known`, catalog ∩ scope **= ∅** (incl. empty `data[]`) | any | full catalog (+ custom row when preference ∉ catalog, K3) | preference | none — a scope that would empty the picker is degenerate and treated exactly as `.unknown` (fail open; K5) |
| `.known`, intersection non-empty | catalog id ∈ scope | catalog ∩ scope | preference | none |
| `.known`, intersection non-empty | catalog id ∉ scope | catalog ∩ scope | default if ∈ scope, else first of catalog ∩ scope | substitution note |
| `.known`, intersection non-empty | custom id ∈ scope | catalog ∩ scope (+ custom row, K3) | preference | none |
| `.known`, intersection non-empty | custom id ∉ scope | catalog ∩ scope (+ custom row, K3) | **preference** | custom-warning note |

Rationale for the custom/catalog asymmetry: a catalog choice was made from a
list WE offered, possibly under a different key — substituting repairs our own
stale offer. A custom id is the user's explicit assertion (D3 already warned
them); overriding it would violate intent primacy. It fails genuinely at
runtime if truly blocked, which then triggers K4d.

A `note` is displayed whenever it is non-nil — including the custom-warning
case where effective == preference (rev 2 fix: rev 1 tied display to
"effective ≠ preference", which made the D3 warning undisplayable). Placement:
the substitution note is the caption under the model picker; the custom
warning REPLACES the informational caption under the custom-id field ("Any
model id from openrouter.ai/models…") while it applies — the two never stack.
Exact copy (tests pin strings): substitution — `"Your key can't use
<preferred display name> — using <effective display name>."`; custom warning
— `"Your key can't use this model. Dictations may insert the raw
transcript."` ("may", not "will": the cache D3 tolerates can be stale).

### Invariants

- **K1** The stored `Config.openRouterModel` is never rewritten by scope
  logic. The existing retired-id migration in `ConfigStore.load` is untouched
  ("retired from the world" stays a load-time migration; "not in this key's
  scope" is runtime derivation).
- **K3** Surfaces are projections of K2. The Settings picker's selection
  displays the EFFECTIVE model; a stored non-catalog custom id keeps its extra
  row (current behavior). The menu-bar submenu checkmark and the
  `"Cleanup Model: …"` title both show the EFFECTIVE model's display name;
  when the effective model is a custom id, no submenu row carries the
  checkmark (the submenu lists catalog ∩ scope only — today's behavior for
  non-catalog ids).
  **Programmatic re-seeds never write**: the pane's seed/re-seed paths
  (`init`, `onAppear`, scope-driven repaints) must not call
  `setCleanupModel`; only a user-initiated picker change does. (Rev 2 fix for
  the rev 1 blocker: with selection showing the effective model, the existing
  re-seed → `onChange` → save wiring would have silently rewritten the
  preference, violating K1/D2. The implementation must make seed-writes
  impossible — e.g. write from the Picker's user-interaction path only — and
  K1's regression test asserts it.)
- **K4** Scope transitions happen only at:
  - (a) cleanup availability entering `.on` (app launch with a key present
    and cleanup enabled counts; see K10), and any pipeline (re)start —
    recognition-language change, onboarding retry, permission grant — while
    availability is `.on` and the scope is still `.unknown`. Idempotent: a
    rebuild with a `.known` scope does not refetch.
  - (b) key save — the scope resets to `.unknown` FIRST, then refetches
    (the old key's scope must never filter the new key's picker);
  - (c) key removal / availability leaving `.on` → reset to `.unknown`;
  - (d) a cleanup failure with HTTP status 404 → a background REFRESH: the
    stale scope stays applied until the fresh result replaces it (no interim
    reversion, no picker flicker); if the refresh itself fails, the scope
    resets to `.unknown` (fail open — the cache is now known-doubtful). At
    most one refresh per failed dictation.
  **Fetch generations** (rev 3, replacing rev 2's bare "coalesce" rule,
  which could install an old key's in-flight result after a key save): the
  scope state carries a generation, bumped by every (b)/(c) reset and every
  availability transition. A fetch is tagged with its start generation; a
  completing fetch whose generation is no longer current is DISCARDED.
  Within one generation at most one fetch is in flight and duplicate
  triggers coalesce into it; a reset never coalesces — it discards the old
  generation's future result and starts its own fetch.
  NEVER on the key-up path: a dictation reads the already-pushed effective
  config (K6).
- **K5** Fail open. `.unknown` — and any degenerate scope per K2 — must
  produce today's exact behavior: full catalog, preference used verbatim,
  zero captions. An empty picker is a worse failure than an optimistic one.
- **K6** Single writer AND single propagation path: every scope transition is
  applied by the same app-layer push funnel that owns
  `CleanupAvailabilityModel` (spec D1 there), and that push re-derives K2,
  re-pushes the effective `CleanupConfig` to the orchestrator
  (`pushEffectiveCleanupConfig`), and rebuilds the status menu
  (`installStatusMenu`). (Rev 2 fix: rev 1 named no propagation trigger, so
  an asynchronously arriving scope would never have reached the orchestrator's
  held config or the baked NSMenu — the feature's core effect. Precisely: the
  app's push idiom is PAIRED `pushEffectiveCleanupConfig()` +
  `installStatusMenu()` call sites, not one shared path; a scope transition
  adds one such site that always does both, and `pushEffectiveCleanupConfig`
  itself starts pushing the K2-derived effective model. Acceptance note: this
  is the first non-user-initiated `installStatusMenu()` caller — verify once
  on the dev Mac that reassigning the menu while the dropdown is open is
  harmless; the expected behavior is the swap landing at the next open.)
- **K7** The fetch is `GET https://openrouter.ai/api/v1/models/user` with the
  Keychain key as Bearer; parse `data[].id` only. Logging stays
  redaction-safe events ("scope fetched n=…", "scope fetch failed: offline");
  response bodies are never logged (they can carry `user_id` — §2). The
  source guard for this is anchored positively: it pins the fetcher's
  `RedactionSafeLog` event calls AND forbids interpolating the response
  `data`/decoded body into any log call — not merely the absence of a token.
- **K8** Cleanup-time error handling is behaviorally unchanged for the user
  (failure → raw insert, glyph, cue; no message-text parsing — 403 is
  ambiguous by status and text is not a contract). Mechanically, K4d needs
  the failure STATUS to reach the app layer, which today it does not:
  `FallbackCleaner` collapses `CleanupError` into a payload-free
  `StatusMessage`. The channel is a new optional observer seam —
  `onCleanupFailure: (CleanupError) -> Void` — invoked by `FallbackCleaner`
  beside its existing degrade path. Wiring: `FallbackCleaner` is constructed
  inside `PipelineFactory.assemble`, so the observer threads through
  `Dependencies` (or a factory parameter) and hops to the main actor the
  same way the existing `statusReporter` does. The app layer maps
  `apiError(status: 404)` to a K4d event and ignores everything else.
  `StatusMessage`, the FSM, and all user-visible behavior stay untouched.
  (Rev 2: rev 1 claimed "two additions only" and under-counted; this seam is
  the honest third.)
- **K9** No persistence (D4). No pre-flight budget check (§2: impossible).
  Translation rides the same single cleanup step — the effective model
  applies to it automatically; nothing translate-specific.
- **K10** The scope fetch runs only while cleanup is effectively ON, and
  never before the hotkey pipeline has started. Raw mode — toggle off or no
  key — keeps its "zero network requests" promise to the letter: no fetch
  fires there (availability gates K4a/K4b). The fetch is asynchronous and
  can never block or delay pipeline readiness. This deliberately AMENDS the
  pinned launch invariant "launch must not read the Keychain secret"
  (`AppRuntimeSourceGuardTests.readyPipelineDoesNotRequireCleanupKeyBeforeHotkeyStart`):
  the amended invariant is "nothing before hotkey start reads the Keychain
  secret; the post-start scope fetch may" — the guard test is updated in the
  same change to pin the new boundary, never silently outgrown. Owner-approved
  2026-08-26 (§9), with the Keychain-prompt acceptance check it carries.

- **K11** The transition logic — reset-first, fetch generations,
  single-flight, the 404 filter, and the fetch/push/rebuild commands
  themselves — is a pure, synchronous reducer in SlovoCore:
  `(state, event) → (state, [command])`, effects as data (directive 4). The
  app funnel's only role is executing emitted commands (run the fetch, push
  the effective config, rebuild the menu) and feeding completions back as
  events. This is what makes §6's behavioral tests real: no test target
  links `Sources/slovo`, so any invariant left in `AppDelegate` would
  silently degrade to a string-scanning source guard —
  `CleanupAvailabilityModel` in SlovoCore is the existing precedent.

### Components

- **SlovoCore**: `CleanupModelScope` value; the K2 derivation (pure,
  `CleanupModelCatalog`-adjacent); the K11 transition reducer;
  `OpenRouterModelScopeFetcher` (URLSession + `OpenRouterKeyProvider` →
  `Set<String>`, same seam style as `OpenRouterCleaner`); the
  `onCleanupFailure` observer seam on `FallbackCleaner` (K8), threaded
  through `PipelineFactory`/`Dependencies`.
- **App layer**: an observable scope holder written only by the availability
  funnel (mirroring `CleanupAvailabilityModel`); `CleanupSettingsPane` and
  `AppDelegate+CleanupMenu` switch from `CleanupModelCatalog.options` to the
  K2 projection; the two caption strings live with the pane; the funnel's
  scope-transition path re-pushes config and rebuilds the menu (K6).
- **Pipeline**: unchanged mechanics — the orchestrator keeps holding the
  pushed `CleanupConfig`; what changes is that the funnel pushes the
  EFFECTIVE model (K2) instead of the raw preference, on the same events as
  today plus scope transitions (K6).

## 5. Non-goals

- No pre-flight credit/budget checks (proven impossible for org budgets).
- No browsing of the key's full model list; the catalog stays curated.
- No persisted scope, no TTL/refresh timers beyond K4's triggers.
- No parsing of error message text; no new error UI beyond existing patterns.
- No network activity while cleanup is effectively off (K10).
- No changes to `StatusMessage`, the FSM, or cue/glyph behavior.

## 6. Verification plan (Cynefin-gated)

**Complicated — full RED→GREEN, each test's breakage documented:**
- K2 derivation: every row of the table, plus mutation sensitivity (swap the
  custom/catalog asymmetry → RED; make substitution rewrite the preference →
  RED via a preference-unchanged assertion; break declaration-order fallback →
  RED).
- K2 degenerate-scope row: catalog-disjoint and empty-`data[]` scopes both
  normalize to fail-open (mutate to fail-closed / empty options → RED).
- K3 seed-guard: a programmatic re-seed with effective ≠ preference must NOT
  invoke `setCleanupModel` (remove the guard → preference rewritten → RED).
- K11 reducer, behaviorally in SlovoCoreTests (this is why K11 exists):
  - K4b: key save resets scope before refetch (mutate to fetch-without-reset
    → stale-scope assertion RED).
  - K4 generations: an in-flight fetch started before a key save completes
    AFTER it — its result is discarded, the new generation's fetch stands
    (mutate to accept stale results → RED). Same for a result landing after
    K4c's reset.
  - K4c: key removal / availability leaving `.on` resets to `.unknown`
    (drop the reset → old scope keeps filtering → RED).
  - K4d/K8: `apiError(404)` yields exactly one refresh command;
    403/offline/`missingKey` yield none (mutate the status filter → RED);
    the stale scope stays applied during the refresh; a failed refresh
    resets to `.unknown`; duplicate triggers within a generation coalesce.
  - K6: every scope transition emits the push-config and rebuild-menu
    commands (drop them → the orchestrator-side config still carries the
    preference → RED).
- D4/K9: a source guard forbids persistence (`UserDefaults` writes) in the
  reducer and fetcher — a silently persisted scope must redden.
- K7: the positively-anchored logging guard described in K7.
- K10: fetch is gated on availability `.on` and ordered strictly after
  hotkey start; the amended launch guard pins the new boundary.
- Source guards updated deliberately: `SettingsSurfaceSourceGuardTests`,
  `AppRuntimeSourceGuardTests` (both the catalog assertion AND the launch
  key-laziness guard), `AppShellPackagingTests`.

**Clear — direct verification, no ceremony:**
- Request shape of the fetcher: one live call per key kind (already evidenced
  by the 2026-08-26 run; re-verify once against the built fetcher).

Full gates before integration: `Scripts/diagnose.sh`; owner hand-check via
`SIGNING_IDENTITY=… Scripts/build_and_run.sh --verify` per the standing
directives. Docs in the same change (pre-PR checklist): the privacy note —
the scope fetch sends the API key and NO user content, and fires only while
cleanup is on — lands in `docs/privacy.md`, the README privacy section, AND
the CLAUDE.md invariant sentence ("only transcript text may leave the
machine") is amended in the same change to name the metadata scope fetch,
so the standing brief never contradicts the shipped behavior.

## 7. Behavior walk-through (the owner's two keys)

- Personal key: scope = 414 ids ⊇ catalog → pickers unchanged, no captions,
  behavior byte-identical to today.
- Corporate key: pickers show 5 of 7 (Claude Haiku 4.5 and Qwen3.6 Flash
  hidden). If the stored choice was Claude Haiku 4.5 → the funnel pushes
  GPT-5.6 Luna as the effective model; Settings selects it and captions
  "Your key can't use Claude Haiku 4.5 — using GPT-5.6 Luna."; the menu shows
  "Cleanup Model: GPT-5.6 Luna". Budget is exhausted, so cleanup still fails
  403 → raw text inserted with glyph+cue, as product intent dictates — but no
  longer *because of a model we offered and shouldn't have*.
- Swap corporate → personal: key save resets scope, refetches; the hidden
  models return and the stored Claude Haiku 4.5 choice revives untouched (K1).
- Key removed / cleanup toggled off: scope `.unknown`, zero network — the
  existing raw-mode promise holds verbatim.

## 8. Part B — catalog refresh (pending, separate change)

All seven ids are alive (§2), so nothing is on fire. A market pass over the
fast-cleanup tier stays queued: candidates in, `slovo-cleanup-benchmark`
(50 samples × repetitions, pass rate + p50/p95) decides, catalog + retired-id
migration updated in the winning change. Not blocked by, and not blocking,
this spec.

## 9. Owner decisions on the rev 2 judgment calls (2026-08-26)

1. **K10 launch-fetch amendment — APPROVED.** The scope fetch runs right
   after hotkey start (async, only with cleanup effectively on), and the
   pinned invariant is deliberately amended to "nothing before hotkey start
   reads the Keychain secret", with the guard test updated in the same
   change. Acceptance check carried into §6: verify on the dev Mac that the
   Keychain read never raises a user prompt after a re-sign/update. If it
   ever does, the fetch moves behind the first user interaction (Settings or
   menu open) — the pre-agreed fallback, honoring the no-focus-stealing rule
   with no other spec changes.
2. **K8 observer seam / K4d self-heal — APPROVED.** The single
   `onCleanupFailure` closure injected at composition stays; one failed
   dictation on a policy-tightened model re-reads the scope in the
   background, so the second one works. Directive 5 trade accepted: the
   smallest mechanism that buys the reliability.
