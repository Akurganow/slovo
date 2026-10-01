import Combine
import os

/// Holds the one `AppState` and its one mutation path. Effects and views follow
/// slices of it through the nanostores verbs `subscribe` and `listen`.
@preconcurrency
@MainActor
public final class AppStore: ObservableObject {
    private static let log = Logger(subsystem: "com.slovo.app", category: "store")
    @Published public private(set) var state: AppState
    private var subscribers: [(AppState) -> Void] = []

    public init(state: AppState) {
        self.state = state.reconciled()
    }

    /// The one mutation path. An equal result publishes nothing; an invalid Config
    /// is refused whole, as ConfigStore.save refuses it.
    public func update(_ mutate: (inout AppState) -> Void) {
        var next = state
        mutate(&next)
        next = next.reconciled()
        guard next != state else { return }
        guard next.config == state.config || ConfigStore.isValid(next.config) else {
            Self.log.error("config save failed")
            return
        }
        state = next
        for subscriber in subscribers { subscriber(state) }
    }

    /// nanostores `subscribe`: now, then on every change of the slice.
    public func subscribe<Slice: Equatable>(
        _ select: @escaping (AppState) -> Slice, _ onChange: @escaping (Slice) -> Void
    ) {
        onChange(select(state))
        listen(select, onChange)
    }

    /// nanostores `listen`: only on later changes of the slice.
    public func listen<Slice: Equatable>(
        _ select: @escaping (AppState) -> Slice, _ onChange: @escaping (Slice) -> Void
    ) {
        var last = select(state)
        subscribers.append { state in
            let slice = select(state)
            guard slice != last else { return }
            last = slice
            onChange(slice)
        }
    }
}
