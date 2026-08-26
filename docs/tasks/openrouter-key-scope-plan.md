# Implementation plan — key-scoped cleanup models

Target: spec `docs/tasks/openrouter-key-scope-and-catalog.md`, 2026-08-26 rev 3.
Branch: `claude/openrouter-keys-models-avvv2p`, local commits only; push happens
on the owner's command when the work is ready for a pull request, not before.
Build/test execution requires a macOS toolchain (`Scripts/diagnose.sh`); the
plan's stages are ordered so every behavior lands test-first regardless of
where the typing happens, but RED/GREEN proof runs happen on the Mac.

## Stage order and rationale

Pure SlovoCore first (S1–S4): everything with real behavior gets a proven-red
test in `SlovoCoreTests` before its implementation exists. App-layer wiring
(S5–S6) comes after, guarded by source guards (no test target links
`Sources/slovo` — spec K11's reason to keep it thin). Docs ride the same
change (S7). Gates and on-Mac acceptance close it (S8).

### S1 — `CleanupModelScope` + the K2 derivation

Covers: K2 (full table), K5 (fail-open rows), D1 (options = catalog ∩ scope),
D2/K1 (derivation never mutates the preference), D3 (custom asymmetry + note),
K3's options content (custom extra row rules).

- New: `Sources/SlovoCore/Cleaner/CleanupModelScope.swift` — the
  `.unknown | .known(Set<String>)` value, and
  `CleanupModelSelection.derive(preference:catalog:scope:) →
  (options: [CleanupModelOption], effective: String, note: Note?)` with
  `Note = .substitution(preferred:effective:) | .customOutsideScope`.
- Tests first: `Tests/SlovoCoreTests/CleanupModelSelectionTests.swift`
  - one test per K2 table row (6 rows), asserting options, effective, note;
  - degenerate-scope rows: catalog-disjoint AND empty-set scopes normalize to
    the `.unknown` row (mutation: fail closed / empty options → RED);
  - custom row present in options for EVERY row where preference ∉ catalog
    (mutation: drop it from the `.unknown` row → RED — the second review's
    finding 3);
  - preference-unchanged: `derive` takes the preference by value and returns
    a distinct `effective` — assert substitution rows leave preference as
    passed (mutation: return effective as new preference → RED);
  - asymmetry: swap the custom/catalog branches → RED;
  - fallback order: default-first, then catalog declaration order (mutation:
    first-in-scope instead of default → RED).

### S2 — the K11 transition reducer

Covers: K4 (a–d, generations), K6 (command emission), K10's gating rule
(fetch only while availability is `.on`; ordering itself is S5), K11.

- New: `Sources/SlovoCore/Cleaner/CleanupScopeReducer.swift` — pure,
  synchronous: `reduce(state, event) → (state, [Command])`.
  State: `{scope, generation, fetchInFlight: Bool}`.
  Events: `availabilityChanged(CleanupAvailability)`, `keySaved`,
  `keyRemoved`, `pipelineStarted`, `fetchCompleted(generation, Result)`,
  `cleanupFailed(status: Int)`.
  Commands: `fetch(generation)`, `pushEffectiveConfig`, `rebuildMenu`.
- Tests first: `Tests/SlovoCoreTests/CleanupScopeReducerTests.swift`
  - K4a: availability → `.on` with scope `.unknown` emits `fetch`;
    `pipelineStarted` with `.known` scope emits none (idempotence mutation →
    RED);
  - K4b: `keySaved` resets scope to `.unknown` AND bumps generation AND
    emits a new `fetch` (mutation: fetch without reset → RED);
  - generations: `fetchCompleted` with a stale generation is discarded —
    state unchanged, no commands (mutation: accept stale → RED); covers both
    the key-save and key-removal races from the second review's finding 1;
  - K4c: `keyRemoved` / availability leaving `.on` resets to `.unknown`
    (mutation: drop the reset → RED);
  - K4d: `cleanupFailed(404)` with no fetch in flight emits one `fetch`;
    403/other statuses emit none (mutation of the filter → RED); during the
    refresh the scope value stays `.known(old)` (stale-until-replaced);
    `fetchCompleted(.failure)` on a 404-refresh generation resets to
    `.unknown`; a second trigger while in flight coalesces (no second fetch);
  - K6: every transition that changes the scope value emits
    `pushEffectiveConfig` + `rebuildMenu` (mutation: drop either → RED);
  - K10 gating: `keySaved` while availability is not `.on` resets state but
    emits NO fetch (raw mode stays zero-network).

### S3 — `OpenRouterModelScopeFetcher`

Covers: K7, D4's no-persistence guard, §2's `user_id` hazard.

- New: `Sources/SlovoCore/Cleaner/OpenRouterModelScopeFetcher.swift` —
  `GET https://openrouter.ai/api/v1/models/user`, Bearer key via
  `OpenRouterKeyProvider`, decode `data[].id` into `Set<String>`, throw on
  non-200/decode failure. Redaction-safe log events only.
- Tests first: `Tests/SlovoCoreTests/OpenRouterModelScopeFetcherTests.swift`
  (stubbed `URLProtocol`, same style as `OpenRouterCleanerTests`):
  request shape (URL, method, auth header, no body); happy-path id set;
  401/404/500 → error; malformed JSON → error; missing key → error.
- Source guards (same file or `RemoveKeySourceGuardTests` style):
  - K7 positive anchor: the fetcher's log calls are the pinned
    `RedactionSafeLog.event` lines AND no log interpolation of the response
    data/decoded body (mutation demo: add a body log → RED);
  - D4: no `UserDefaults` (or any persistence API) reference in the fetcher
    or reducer files (mutation demo: add a UserDefaults write → RED).

### S4 — the K8 failure-observer seam

Covers: K8 (the one new cross-layer mechanism, §9.2).

- Change: `FallbackCleaner` gains optional
  `onCleanupFailure: ((CleanupError) -> Void)?`, invoked beside the existing
  degrade path; threaded through `PipelineFactory.assemble` via
  `Dependencies` (or a factory parameter). `StatusMessage`/FSM untouched.
- Tests first: extend `Tests/SlovoCoreTests/` fallback-cleaner coverage:
  observer receives the thrown `CleanupError` on failure; not invoked on
  success; existing `StatusMessage` pins stay green (proof nothing user-
  visible changed).

### S5 — app-layer wiring (funnel, fetch site, guards)

Covers: K6 (paired push+rebuild call site), K10 (fetch strictly after
`hotkeyMonitor.start()`, async, availability-gated — §9.1 as approved),
K11's division of labor, the amended launch invariant.

- Change: `AppDelegate` (+`AppComposition`/`AppDelegate+Settings`): an
  observable scope holder (mirroring `CleanupAvailabilityModel`, funnel as
  its only writer); the funnel executes reducer commands — runs the fetcher
  (tagged with generation, results fed back as `fetchCompleted`), calls
  `pushEffectiveCleanupConfig()` (now deriving the K2 effective model into
  the pushed `CleanupConfig`) and `installStatusMenu()`; the `keySaved` /
  `keyRemoved` / availability events fire from the existing key-save/remove/
  toggle paths; `pipelineStarted` fires right after the hotkey start success
  point; the K8 observer hops to the main actor (same pattern as
  `statusReporter`) and feeds `cleanupFailed(status:)`.
- Source guards updated IN THE SAME CHANGE (spec §6 list, deliberately):
  - `AppRuntimeSourceGuardTests`: launch guard re-pinned to the amended
    boundary ("nothing before hotkey start reads the Keychain secret; the
    post-start scope fetch may"); catalog assertion → K2-projection
    assertion; new guard: the scope fetch call site sits after the hotkey
    start success point and inside the availability-`.on` gate;
  - `AppShellPackagingTests` catalog assertion likewise.

### S6 — UI projection (Settings pane + menu)

Covers: K3 (all of it), D1 on both surfaces, the pinned caption copy.

- Change: `CleanupSettingsPane` — options/selection/captions from the K2
  projection via the scope holder (`@ObservedObject`, like availability);
  selection displays the EFFECTIVE model; **seed-guard**: the preference
  write happens only on the Picker's user-interaction path (computed-binding
  pattern of the master toggle), so `init`/`onAppear`/repaint re-seeds can
  never call `setCleanupModel`; substitution caption under the picker;
  custom warning replaces the informational caption while it applies; copy
  exactly as pinned in the spec.
- Change: `AppDelegate+CleanupMenu` + `DictationMenuBuilder` — submenu rows
  = K2 options; checkmark and `"Cleanup Model: …"` title show the effective
  model's display name; no checkmark when effective is a custom id.
- Source guards: `SettingsSurfaceSourceGuardTests` re-pinned to the
  projection + a seed-guard source assertion (the pane contains no
  `setCleanupModel` call reachable from `onAppear`/init paths); caption
  strings pinned.

### S7 — docs, same change

Covers: spec §6 docs list. `docs/privacy.md` + README privacy section gain
the scope-fetch note (API key only, no user content, only while cleanup is
on); CLAUDE.md's "only transcript text may leave the machine" sentence is
amended to name the metadata scope fetch.

### S8 — gates and acceptance (on the Mac)

1. Full `Scripts/diagnose.sh` (build, tests, strict lint).
2. Independent audit of the integrated result (correctness, complexity,
   design, test sensitivity) — separate clean agent, per the standing
   directives.
3. Clear-domain live check: one `models/user` call per key kind against the
   built fetcher (personal + corporate), confirming the 2026-08-26 evidence.
4. Acceptance checks from the spec: (a) §9.1 — Keychain read after a
   re-sign/update raises no prompt; if it ever does, move the fetch behind
   the first user interaction (pre-agreed fallback, no other spec change);
   (b) K6 — menu reassignment while the dropdown is open is harmless.
5. Merge into local main, dev build via
   `SIGNING_IDENTITY="Developer ID Application: Alexander Kurganov
   (ZN8H5SF4R7)" Scripts/build_and_run.sh --verify`, hand to the owner.
6. Push + PR only on the owner's explicit command.

## Traceability matrix (spec item → stage)

| Spec item | Stage |
| --- | --- |
| D1 hide unavailable | S1 (options), S6 (both surfaces) |
| D2 / K1 preference never rewritten | S1 (derive), S6 (seed-guard), S5 (pushed config is derived value) |
| D3 custom accept+warn | S1 (note), S6 (caption) |
| D4 in-memory only | S2 (state), S3 (no-persistence guard) |
| K2 table (all 6 rows + degenerate) | S1 |
| K3 projections, effective display, seed-guard, checkmark carve-out, captions | S6 |
| K4a incl. pipeline-restart idempotence | S2, S5 (event source) |
| K4b reset-first | S2 |
| K4c reset on removal/off | S2 |
| K4d 404 refresh, stale-until-replaced, fail→unknown, once per failure | S2, S4 (status channel), S5 (main-actor feed) |
| K4 fetch generations | S2 |
| K5 fail open | S1 (rows), S2 (failure events) |
| K6 single writer + paired push/rebuild | S2 (commands), S5 (call site), source guards S5 |
| K7 fetch + redaction-safe logging | S3 |
| K8 observer seam | S4, S5 (actor hop) |
| K9 no persistence / no budget preflight / translate untouched | S2–S3 guards; no code = nothing to do beyond guards |
| K10 gating + ordering + amended launch guard | S2 (gating), S5 (ordering + guard) |
| K11 reducer, effects as data | S2, S5 (division of labor) |
| §2 `user_id` log hazard | S3 (K7 guard) |
| §6 every listed test | S1–S6 as mapped above |
| §6 docs list | S7 |
| §7 walk-through scenarios | end-to-end covered by S1/S2 tests + S8.3 live check |
| §9.1 / §9.2 approvals + acceptance checks | S5 (fetch site), S4 (seam), S8.4 |
| §8 Part B catalog refresh | OUT OF SCOPE — separate change |

## Out of scope

Part B (catalog market refresh); any provider-routing/fallback-`models`
usage; any change to `StatusMessage`, FSM, cues, glyphs; any persistence.
