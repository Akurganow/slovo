/// App-funnel state for the key's model scope (spec rev 3 §4 K4/K11).
public struct CleanupScopeState: Equatable, Sendable {
    public var scope: CleanupModelScope = .unknown
    public var generation: Int = 0
    public var fetchInFlight: Bool = false
    public var cleanupIsOn: Bool = false
    /// K10 ordering gate: no fetch command is emitted before the app reports
    /// the hotkey pipeline started (set by `.pipelineStarted`, never cleared —
    /// restarts re-send the event, which is idempotent on the flag).
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

public enum CleanupScopeCommand: Equatable, Sendable {
    case fetch(generation: Int)
    case pushEffectiveConfig
    case rebuildMenu
}

/// Pure transition logic: the app layer executes the returned commands and feeds
/// completions back as events; it decides nothing itself (K11, effects as data).
public enum CleanupScopeReducer {
    public static func reduce(
        _ state: CleanupScopeState, _ event: CleanupScopeEvent
    ) -> (state: CleanupScopeState, commands: [CleanupScopeCommand]) {
        var s = state
        switch event {
        case .availabilityChanged(let isOn):
            // A non-transition is a no-op: a pipeline restart must not reset a
            // known scope, bump the generation, or refetch (K4a idempotence).
            guard isOn != s.cleanupIsOn else { return (s, []) }
            s.cleanupIsOn = isOn
            s.generation += 1        // every availability TRANSITION bumps (K4)
            s.fetchInFlight = false  // any in-flight result is now stale
            var commands = resetScope(&s)
            commands += fetchIfReady(&s)   // K4a; leaving .on is K4c (reset only)
            return (s, commands)
        case .pipelineStarted:
            s.pipelineHasStarted = true
            if s.scope != .unknown {
                // A rebuilt orchestrator was seeded with the raw preference;
                // re-derive without reset or refetch (K6 + K4a idempotence).
                return (s, [.pushEffectiveConfig, .rebuildMenu])
            }
            guard !s.fetchInFlight else { return (s, []) }
            // Two statements on purpose: `return (s, fetchIfReady(&s))` copies `s`
            // BEFORE the inout call mutates it (left-to-right tuple evaluation) and
            // would return the pre-mutation state — fetchInFlight would never latch.
            let commands = fetchIfReady(&s)
            return (s, commands)
        case .keySaved:
            s.generation += 1
            s.fetchInFlight = false
            var commands = resetScope(&s)   // reset FIRST (K4b)
            commands += fetchIfReady(&s)    // K10: gated on .on AND pipeline started
            return (s, commands)
        case .keyRemoved:
            s.generation += 1
            s.fetchInFlight = false
            let commands = resetScope(&s)   // K4c; two statements — see .pipelineStarted
            return (s, commands)
        case .fetchCompleted(let generation, let ids):
            guard generation == s.generation else { return (s, []) }  // stale → discarded
            s.fetchInFlight = false
            guard let ids else {
                let commands = resetScope(&s)  // failed refresh fails open; two statements — see .pipelineStarted
                return (s, commands)
            }
            s.scope = .known(ids)
            return (s, [.pushEffectiveConfig, .rebuildMenu])
        case .cleanupFailed(let error):
            // The whole K4d filter lives here (K11). No message-text parsing (K8).
            guard case .apiError(status: 404) = error else { return (s, []) }
            guard s.cleanupIsOn, s.pipelineHasStarted, !s.fetchInFlight else { return (s, []) }
            s.fetchInFlight = true
            // Same generation: the stale scope stays applied until replaced (K4d).
            return (s, [.fetch(generation: s.generation)])
        }
    }

    private static func resetScope(_ s: inout CleanupScopeState) -> [CleanupScopeCommand] {
        guard s.scope != .unknown else { return [] }
        s.scope = .unknown
        return [.pushEffectiveConfig, .rebuildMenu]
    }

    /// The single fetch gate: cleanup effectively on, hotkey started (K10),
    /// scope unknown, nothing already in flight.
    private static func fetchIfReady(_ s: inout CleanupScopeState) -> [CleanupScopeCommand] {
        guard s.cleanupIsOn, s.pipelineHasStarted, s.scope == .unknown, !s.fetchInFlight else { return [] }
        s.fetchInFlight = true
        return [.fetch(generation: s.generation)]
    }
}
