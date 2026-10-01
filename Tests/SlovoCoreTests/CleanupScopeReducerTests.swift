import Testing
import SlovoCore

@Suite("CleanupScopeReducer (spec rev 3 §4 K4/K6/K10/K11)")
struct CleanupScopeReducerTests {
    private func reduce(_ s: CleanupScopeState, _ e: CleanupScopeEvent) -> CleanupScopeState {
        CleanupScopeReducer.reduce(s, e)
    }
    /// Launch sequence as the store sends it: availability edge first, then
    /// pipeline start — leaves the initial fetch in flight.
    private func ready() -> CleanupScopeState {
        reduce(reduce(CleanupScopeState(), .availabilityChanged(isOn: true)), .pipelineStarted)
    }
    private func known(_ ids: Set<String>) -> CleanupScopeState {
        let s = ready()
        return reduce(s, .fetchCompleted(generation: s.generation, ids: ids))
    }

    // K4a + K10 ordering: availability alone must NOT fetch (hotkey has not
    // started); pipelineStarted then does, under the same generation.
    @Test
    func launchFetchWaitsForPipelineStart() {
        let s1 = reduce(CleanupScopeState(), .availabilityChanged(isOn: true))
        #expect(!s1.fetchInFlight)
        let s2 = reduce(s1, .pipelineStarted)
        #expect(s2.fetchInFlight)
        #expect(s2.generation == s1.generation)
    }

    // K4a idempotence, the APP's actual restart sequence: a pipeline rebuild with a
    // known scope — redundant edge + pipelineStarted — must not reset, bump, or
    // refetch. The rebuilt orchestrator is seeded with the effective config, which
    // AppShellPackagingTests pins.
    // Sensitivity: drop the same-value no-op guard → the s1 == s assertion goes RED.
    @Test
    func pipelineRestartWithKnownScopeKeepsTheScope() {
        let s = known(["a/b"])
        let s1 = reduce(s, .availabilityChanged(isOn: true))  // redundant edge
        #expect(s1 == s)
        let s2 = reduce(s1, .pipelineStarted)
        #expect(s2.scope == .known(["a/b"]))
        #expect(s2.generation == s.generation)
        #expect(!s2.fetchInFlight)
    }

    // K10: the reducer's ordering gate holds on EVERY fetch-starting arm,
    // including K4d. Sensitivity: drop the pipelineHasStarted conjunct from
    // .cleanupFailed → RED (v3-verification B6).
    @Test
    func cleanupFailedBeforePipelineStartIsIgnored() {
        let s = reduce(CleanupScopeState(), .availabilityChanged(isOn: true))
        #expect(reduce(s, .cleanupFailed(.apiError(status: 404))) == s)
    }

    // K10 corner: a key save before hotkey start (pending onboarding) never fetches.
    @Test
    func keySavedBeforePipelineStartDoesNotFetch() {
        let s = reduce(CleanupScopeState(), .availabilityChanged(isOn: true))
        #expect(!reduce(s, .keySaved).fetchInFlight)
    }

    // K4a restart arm, POSITIVE half: a restart with .on + unknown scope DOES fetch.
    @Test
    func pipelineRestartWithUnknownScopeFetches() {
        var s = ready()
        s.fetchInFlight = false  // the launch fetch failed silently
        let s2 = reduce(s, .pipelineStarted)
        #expect(s2.fetchInFlight)
        #expect(s2.generation == s.generation)
    }

    // K4b: key save resets FIRST, bumps the generation, then fetches.
    // Sensitivity: fetch without reset → the scope assertion goes RED.
    @Test
    func keySavedResetsBumpsThenFetches() {
        let s = known(["a/b"])
        let s2 = reduce(s, .keySaved)
        #expect(s2.scope == .unknown)
        #expect(s2.generation == s.generation + 1)
        #expect(s2.fetchInFlight)
    }

    // K4 generations: a stale in-flight result landing AFTER a key-save reset is discarded.
    @Test
    func staleResultAfterKeySaveIsDiscarded() {
        var s = ready()                                  // launch fetch in flight
        let staleGen = s.generation
        s = reduce(s, .keySaved)                         // gen bumped, new fetch
        #expect(reduce(s, .fetchCompleted(generation: staleGen, ids: ["old/key-model"])) == s)
    }

    // K4 generations, §6's "same for a result landing after K4c's reset".
    @Test
    func staleResultAfterKeyRemovalIsDiscarded() {
        var s = ready()                                  // launch fetch in flight
        let staleGen = s.generation
        s = reduce(s, .keyRemoved)
        #expect(reduce(s, .fetchCompleted(generation: staleGen, ids: ["old/key-model"])) == s)
    }

    // K4 generations: every availability TRANSITION bumps; a non-transition does not.
    @Test
    func availabilityTransitionsBumpGeneration() {
        let s1 = reduce(CleanupScopeState(), .availabilityChanged(isOn: true))
        #expect(reduce(s1, .availabilityChanged(isOn: true)).generation == s1.generation)
        let s2 = reduce(s1, .availabilityChanged(isOn: false))
        #expect(s2.generation == s1.generation + 1)
        #expect(reduce(s2, .availabilityChanged(isOn: true)).generation == s2.generation + 1)
    }

    // K4c: key removal / leaving .on resets to .unknown, bumps, and starts no fetch.
    // Sensitivity: drop the reset → old scope keeps filtering → RED.
    @Test
    func keyRemovedAndAvailabilityOffReset() {
        let s = known(["a/b"])
        for event in [CleanupScopeEvent.keyRemoved, .availabilityChanged(isOn: false)] {
            let s2 = reduce(s, event)
            #expect(s2.scope == .unknown)
            #expect(s2.generation == s.generation + 1)
            #expect(!s2.fetchInFlight)
        }
    }

    // K4d: only apiError(404) triggers the refresh; the WHOLE filter is reducer-owned (K11).
    // Sensitivity: widen the filter to any apiError → the 403 case goes RED.
    @Test
    func only404TriggersRefresh() {
        let s = known(["a/b"])
        let s2 = reduce(s, .cleanupFailed(.apiError(status: 404)))
        #expect(s2.fetchInFlight)
        #expect(s2.generation == s.generation)
        #expect(s2.scope == .known(["a/b"]))  // stale-until-replaced: no interim reversion
        for error in [
            CleanupError.apiError(status: 403), .offline, .missingKey,
            .rateLimited(retryAfter: nil), .refused,
        ] {
            #expect(reduce(s, .cleanupFailed(error)) == s)
        }
    }

    // K4d: a FAILED refresh of a known scope fails open to .unknown.
    @Test
    func failedRefreshFailsOpen() {
        let s = reduce(known(["a/b"]), .cleanupFailed(.apiError(status: 404)))
        let s2 = reduce(s, .fetchCompleted(generation: s.generation, ids: nil))
        #expect(s2.scope == .unknown)
        #expect(!s2.fetchInFlight)
    }

    // K6: a successful fetch makes the scope known and settles the fetch; the push
    // and the menu follow from the state.
    // Sensitivity: drop `s.scope = .known(ids)` → RED.
    @Test
    func successfulFetchMakesTheScopeKnown() {
        let s = ready()
        let s2 = reduce(s, .fetchCompleted(generation: s.generation, ids: ["a/b"]))
        #expect(s2.scope == .known(["a/b"]))
        #expect(!s2.fetchInFlight)
        #expect(s2.generation == s.generation)
    }

    // K10 gating: raw mode stays zero-network — key events while off never fetch.
    @Test
    func keySavedWhileOffDoesNotFetch() {
        let s = reduce(CleanupScopeState(), .keySaved)
        #expect(s.scope == .unknown)
        #expect(!s.fetchInFlight)
    }
}
