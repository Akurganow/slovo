import Testing
import SlovoCore

@Suite("CleanupScopeReducer (spec rev 3 §4 K4/K6/K10/K11)")
struct CleanupScopeReducerTests {
    private func reduce(_ s: CleanupScopeState, _ e: CleanupScopeEvent) -> (state: CleanupScopeState, commands: [CleanupScopeCommand]) {
        CleanupScopeReducer.reduce(s, e)
    }
    private func hasFetch(_ c: [CleanupScopeCommand]) -> Bool {
        c.contains { if case .fetch = $0 { true } else { false } }
    }
    /// Launch sequence as the app sends it (Task 5): availability edge first,
    /// then pipeline start — leaves the initial fetch in flight.
    private func ready() -> CleanupScopeState {
        var s = reduce(CleanupScopeState(), .availabilityChanged(isOn: true)).state
        s = reduce(s, .pipelineStarted).state
        return s
    }
    private func known(_ ids: Set<String>) -> CleanupScopeState {
        let s = ready()
        return reduce(s, .fetchCompleted(generation: s.generation, ids: ids)).state
    }

    // K4a + K10 ordering: availability alone must NOT fetch (hotkey has not
    // started); pipelineStarted then does.
    @Test
    func launchFetchWaitsForPipelineStart() {
        let (s1, c1) = reduce(CleanupScopeState(), .availabilityChanged(isOn: true))
        #expect(!hasFetch(c1))
        let (s2, c2) = reduce(s1, .pipelineStarted)
        #expect(c2 == [.fetch(generation: s2.generation)])
        #expect(s2.fetchInFlight)
    }

    // K4a idempotence + K6, the APP's actual restart sequence: a pipeline rebuild
    // with a known scope — redundant edge + pipelineStarted — must not reset,
    // bump, or refetch, but MUST re-push: the rebuilt orchestrator was seeded
    // from the raw preference. Sensitivity: drop the same-value no-op guard →
    // the s1 == s assertion goes RED; drop the re-push → the c2 assertion goes
    // RED (v3-verification B3, the silent K6 regression).
    @Test
    func pipelineRestartWithKnownScopeRepushesWithoutReset() {
        let s = known(["a/b"])
        let (s1, c1) = reduce(s, .availabilityChanged(isOn: true))  // redundant edge
        #expect(s1 == s)
        #expect(c1.isEmpty)
        let (s2, c2) = reduce(s1, .pipelineStarted)
        #expect(s2.scope == .known(["a/b"]))
        #expect(c2 == [.pushEffectiveConfig, .rebuildMenu])
        #expect(!hasFetch(c2))
    }

    // K10: the reducer's ordering gate holds on EVERY fetch-emitting arm,
    // including K4d. Sensitivity: drop the pipelineHasStarted conjunct from
    // .cleanupFailed → RED (v3-verification B6).
    @Test
    func cleanupFailedBeforePipelineStartIsIgnored() {
        let s = reduce(CleanupScopeState(), .availabilityChanged(isOn: true)).state
        #expect(reduce(s, .cleanupFailed(.apiError(status: 404))).commands.isEmpty)
    }

    // K10 corner: a key save before hotkey start (pending onboarding) never fetches.
    @Test
    func keySavedBeforePipelineStartDoesNotFetch() {
        let s = reduce(CleanupScopeState(), .availabilityChanged(isOn: true)).state
        #expect(!hasFetch(reduce(s, .keySaved).commands))
    }

    // K4a restart arm, POSITIVE half: a restart with .on + unknown scope DOES fetch.
    @Test
    func pipelineRestartWithUnknownScopeFetches() {
        var s = ready()
        s.fetchInFlight = false  // the launch fetch failed silently
        let (s2, c) = reduce(s, .pipelineStarted)
        #expect(c == [.fetch(generation: s2.generation)])
    }

    // K4b: key save resets FIRST, bumps the generation, then fetches.
    // Sensitivity: fetch without reset → the scope assertion goes RED.
    @Test
    func keySavedResetsBumpsThenFetches() {
        let s = known(["a/b"])
        let (s2, c) = reduce(s, .keySaved)
        #expect(s2.scope == .unknown)
        #expect(s2.generation == s.generation + 1)
        #expect(c.contains(.pushEffectiveConfig) && c.contains(.rebuildMenu))
        #expect(c.contains(.fetch(generation: s.generation + 1)))
    }

    // K4 generations: a stale in-flight result landing AFTER a key-save reset is discarded.
    @Test
    func staleResultAfterKeySaveIsDiscarded() {
        var s = ready()                                  // launch fetch in flight
        let staleGen = s.generation
        s = reduce(s, .keySaved).state                   // gen bumped, new fetch
        let (s2, c) = reduce(s, .fetchCompleted(generation: staleGen, ids: ["old/key-model"]))
        #expect(s2 == s)
        #expect(c.isEmpty)
    }

    // K4 generations, §6's "same for a result landing after K4c's reset".
    @Test
    func staleResultAfterKeyRemovalIsDiscarded() {
        var s = ready()                                  // launch fetch in flight
        let staleGen = s.generation
        s = reduce(s, .keyRemoved).state
        let (s2, c) = reduce(s, .fetchCompleted(generation: staleGen, ids: ["old/key-model"]))
        #expect(s2 == s)
        #expect(c.isEmpty)
    }

    // K4 generations: every availability TRANSITION bumps; a non-transition does not.
    @Test
    func availabilityTransitionsBumpGeneration() {
        let s1 = reduce(CleanupScopeState(), .availabilityChanged(isOn: true)).state
        #expect(reduce(s1, .availabilityChanged(isOn: true)).state.generation == s1.generation)
        let s2 = reduce(s1, .availabilityChanged(isOn: false)).state
        #expect(s2.generation == s1.generation + 1)
        #expect(reduce(s2, .availabilityChanged(isOn: true)).state.generation == s2.generation + 1)
    }

    // K4c: key removal / leaving .on resets to .unknown and pushes the repaint.
    // Sensitivity: drop the reset → old scope keeps filtering → RED.
    @Test
    func keyRemovedAndAvailabilityOffReset() {
        for event in [CleanupScopeEvent.keyRemoved, .availabilityChanged(isOn: false)] {
            let (s2, c) = reduce(known(["a/b"]), event)
            #expect(s2.scope == .unknown)
            #expect(c.contains(.pushEffectiveConfig) && c.contains(.rebuildMenu))
            #expect(!hasFetch(c))
        }
    }

    // K4d: only apiError(404) triggers the refresh; the WHOLE filter is reducer-owned (K11).
    // Sensitivity: widen the filter to any apiError → the 403 case goes RED.
    @Test
    func only404TriggersRefresh() {
        let s = known(["a/b"])
        let (s2, c) = reduce(s, .cleanupFailed(.apiError(status: 404)))
        #expect(c == [.fetch(generation: s2.generation)])
        #expect(s2.scope == .known(["a/b"]))  // stale-until-replaced: no interim reversion
        for error in [CleanupError.apiError(status: 403), .offline, .missingKey,
                      .rateLimited(retryAfter: nil), .refused] {
            #expect(reduce(s, .cleanupFailed(error)).commands.isEmpty)
        }
    }

    // K4d single-flight: a second 404 while the refresh is in flight coalesces.
    @Test
    func refreshInFlightCoalesces() {
        let mid = reduce(known(["a/b"]), .cleanupFailed(.apiError(status: 404))).state
        #expect(reduce(mid, .cleanupFailed(.apiError(status: 404))).commands.isEmpty)
    }

    // K4d: a FAILED refresh of a known scope fails open to .unknown.
    @Test
    func failedRefreshFailsOpen() {
        let s = reduce(known(["a/b"]), .cleanupFailed(.apiError(status: 404))).state
        let (s2, c) = reduce(s, .fetchCompleted(generation: s.generation, ids: nil))
        #expect(s2.scope == .unknown)
        #expect(c.contains(.pushEffectiveConfig) && c.contains(.rebuildMenu))
    }

    // K6: a successful fetch pushes the effective config and rebuilds the menu.
    // Sensitivity: drop either command → RED (the rev 1 review's 404-loop finding).
    @Test
    func successfulFetchPushesAndRebuilds() {
        let s = ready()
        let (s2, c) = reduce(s, .fetchCompleted(generation: s.generation, ids: ["a/b"]))
        #expect(s2.scope == .known(["a/b"]))
        #expect(c == [.pushEffectiveConfig, .rebuildMenu])
    }

    // K10 gating: raw mode stays zero-network — key events while off never fetch.
    @Test
    func keySavedWhileOffDoesNotFetch() {
        let (s, c) = reduce(CleanupScopeState(), .keySaved)
        #expect(s.scope == .unknown)
        #expect(!hasFetch(c))
    }
}
