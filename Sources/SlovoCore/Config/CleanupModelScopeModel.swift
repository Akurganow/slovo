import Combine

/// The observable app-layer holder of the key's model scope, the exact mirror of
/// `CleanupAvailabilityModel` (spec rev 3 §4 Components): the app's push funnel
/// is its single writer, and surfaces render THIS object instead of snapshots.
@preconcurrency
@MainActor
public final class CleanupModelScopeModel: ObservableObject {
    @Published public private(set) var scope: CleanupModelScope

    public init(scope: CleanupModelScope) {
        self.scope = scope
    }

    /// Synchronous on purpose: observers must see the new value in the same
    /// runloop turn — the invariant's testability bound.
    public func update(_ scope: CleanupModelScope) {
        self.scope = scope
    }
}
