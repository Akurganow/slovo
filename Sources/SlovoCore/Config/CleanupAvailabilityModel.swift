import Combine

/// The observable app-layer holder of the effective cleanup state (the
/// observation invariant, spec D1): surfaces that must reflect a mutation
/// within one runloop — the Settings pane — render THIS object instead of
/// snapshotting a derived value. The app's push funnel is its single writer,
/// and `CleanupAvailability.derive` stays the only derivation of the value
/// it carries. Combine's `ObservableObject`, not the `@Observable` macro, on
/// purpose: the macro cannot expand under `swiftlint analyze` (the
/// swift-plugin-server replay fails), which would break the strict-lint gate.
@preconcurrency
@MainActor
public final class CleanupAvailabilityModel: ObservableObject {
    // private(set) so the funnel's `update` is the one mutation path the
    // compiler admits outside this type.
    @Published public private(set) var availability: CleanupAvailability

    public init(availability: CleanupAvailability) {
        self.availability = availability
    }

    /// Replaces the published state. Synchronous on purpose: observers must see
    /// the new value in the same runloop turn — the invariant's testability bound.
    public func update(_ availability: CleanupAvailability) {
        self.availability = availability
    }
}
