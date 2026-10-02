/// The key's model-scope state (spec rev 3 §4 K4/K11), held as `AppState.cleanupScope`.
public struct CleanupScopeState: Equatable, Sendable {
    public var scope: CleanupModelScope = .unknown
    public var generation: Int = 0
    public var fetchInFlight: Bool = false
    public var cleanupIsOn: Bool = false
    /// K10 ordering gate: no fetch starts before the app reports the hotkey
    /// pipeline started (set by `.pipelineStarted`, never cleared — restarts
    /// re-send the event, which is idempotent on the flag).
    public var pipelineHasStarted: Bool = false
    public init() {}
}

public enum CleanupScopeEvent: Sendable {
    case availabilityChanged(isOn: Bool)
    case pipelineStarted
    case keySaved
    case keyRemoved
    /// `ids == nil` means the fetch failed.
    case fetchCompleted(generation: Int, ids: Set<String>?)
    case cleanupFailed(CleanupError)
}

/// Pure transition logic over the scope state. The store applies each event and
/// derives what follows from the result: the fetch from `AppState.pendingFetch`,
/// the orchestrator push and the menu from the selectors.
public enum CleanupScopeReducer {
    public static func reduce(_ state: CleanupScopeState, _ event: CleanupScopeEvent) -> CleanupScopeState {
        var s = state
        switch event {
        case .availabilityChanged(let isOn):
            // A non-transition is a no-op: a pipeline restart must not reset a
            // known scope, bump the generation, or refetch (K4a idempotence).
            guard isOn != s.cleanupIsOn else { return s }
            s.cleanupIsOn = isOn
            s.generation += 1        // every availability TRANSITION bumps (K4)
            s.fetchInFlight = false  // any in-flight result is now stale
            resetScope(&s)
            fetchIfReady(&s)         // K4a; leaving .on is K4c (reset only)
            return s
        case .pipelineStarted:
            s.pipelineHasStarted = true
            // A known scope survives a pipeline restart: no reset, no refetch (K4a).
            if s.scope != .unknown { return s }
            fetchIfReady(&s)
            return s
        case .keySaved:
            s.generation += 1
            s.fetchInFlight = false
            resetScope(&s)           // reset FIRST (K4b)
            fetchIfReady(&s)         // K10: gated on .on AND pipeline started
            return s
        case .keyRemoved:
            s.generation += 1
            s.fetchInFlight = false
            resetScope(&s)           // K4c
            return s
        case .fetchCompleted(let generation, let ids):
            guard generation == s.generation else { return s }  // stale → discarded
            s.fetchInFlight = false
            guard let ids else {
                resetScope(&s)       // a failed refresh fails open
                return s
            }
            s.scope = .known(ids)
            return s
        case .cleanupFailed(let error):
            // The whole K4d filter lives here (K11). No message-text parsing (K8).
            guard case .apiError(status: 404) = error else { return s }
            guard s.cleanupIsOn, s.pipelineHasStarted else { return s }
            s.fetchInFlight = true
            // Same generation: the stale scope stays applied until replaced (K4d).
            return s
        }
    }

    private static func resetScope(_ s: inout CleanupScopeState) {
        s.scope = .unknown
    }

    /// The single fetch gate: cleanup effectively on, hotkey started (K10),
    /// scope unknown, nothing already in flight.
    private static func fetchIfReady(_ s: inout CleanupScopeState) {
        guard s.cleanupIsOn, s.pipelineHasStarted, s.scope == .unknown, !s.fetchInFlight else { return }
        s.fetchInFlight = true
    }
}
