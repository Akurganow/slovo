import Synchronization
import Testing

import SlovoCore
import SlovoTestSupport

// The store's contract: one synchronous mutation path that publishes only real
// changes, refuses an invalid Config whole, and hands each slice to its
// subscribers after the state is committed.
@Suite("App store")
@MainActor
struct AppStoreTests {
    private static func makeStore() -> AppStore {
        AppStore(state: AppState(config: Config(), isOpenRouterKeyPresent: true))
    }

    /// A pane renders the store, so a write must be visible before `update`
    /// returns: the same runloop turn, ahead of any orchestrator hop.
    /// Stated sensitivity: defer the assignment through a `Task` → RED.
    @Test
    func updatePublishesSynchronously() {
        let store = Self.makeStore()
        let notifications = Mutex(0)
        let subscription = store.objectWillChange.sink { notifications.withLock { $0 += 1 } }
        store.update { $0.config.writingStyle = .formal }
        #expect(notifications.withLock { $0 } == 1, "the change must notify observers before update() returns")
        #expect(store.state.config.writingStyle == .formal)
        subscription.cancel()
    }

    /// `@Published` publishes an equal value, so without the guard every no-op
    /// write would re-render every pane.
    /// Stated sensitivity: delete `guard next != state` → RED.
    @Test
    func equalUpdatePublishesNothing() {
        let store = Self.makeStore()
        let notifications = Mutex(0)
        let subscription = store.objectWillChange.sink { notifications.withLock { $0 += 1 } }
        var delivered: [WritingStyle] = []
        store.listen(\.config.writingStyle) { delivered.append($0) }
        store.update { $0.config.writingStyle = $0.config.writingStyle }
        #expect(notifications.withLock { $0 } == 0, "a write of the current value must publish nothing")
        #expect(delivered.isEmpty)
        subscription.cancel()
    }

    /// The store validates before it commits, as `ConfigStore.save` does, so a
    /// refused pair leaves every field, and every observer, untouched.
    /// Stated sensitivity: delete the validation guard → RED.
    @Test
    func invalidConfigIsRefusedWhole() {
        let store = Self.makeStore()
        let before = store.state
        let notifications = Mutex(0)
        let subscription = store.objectWillChange.sink { notifications.withLock { $0 += 1 } }
        store.update {
            $0.config.writingStyle = .formal
            $0.config.translateTrigger = $0.config.trigger
        }
        #expect(store.state == before, "a colliding key pair must leave the whole state as it was")
        #expect(notifications.withLock { $0 } == 0)
        subscription.cancel()
    }

    /// Stated sensitivity: delete `guard slice != last` → RED.
    @Test
    func listenFiresOnlyOnSliceChange() {
        let store = Self.makeStore()
        var delivered: [Bool] = []
        store.listen(\.config.mutesSystemAudioWhileDictating) { delivered.append($0) }
        store.update { $0.config.writingStyle = .formal }
        store.update { $0.config.mutesSystemAudioWhileDictating = false }
        store.update { $0.config.useSpellCheckHints = false }
        store.update { $0.config.mutesSystemAudioWhileDictating = true }
        #expect(delivered == [false, true], "a slice subscriber runs once per distinct value and never for another field")
    }

    /// Stated sensitivity: drop the immediate call from `subscribe` → RED.
    @Test
    func subscribeRunsImmediately() {
        let store = Self.makeStore()
        var delivered: [Bool] = []
        store.subscribe(\.config.mutesSystemAudioWhileDictating) { delivered.append($0) }
        #expect(delivered == [true], "subscribe must deliver the current slice before it returns")
    }

    /// `@Published` delivers in `willSet`, so a `$state` subscriber reading
    /// `store.state` would see the previous value.
    /// Stated sensitivity: deliver through `$state.sink` instead → RED.
    @Test
    func subscriberReadsTheCommittedState() {
        let store = Self.makeStore()
        var seen: [WritingStyle?] = []
        store.listen(\.config.writingStyle) { [weak store] _ in seen.append(store?.state.config.writingStyle) }
        store.update { $0.config.writingStyle = .formal }
        #expect(seen == [.formal], "a subscriber must read the state that triggered it")
    }

    /// A model id written live is the id the next launch loads: a superseded id
    /// follows its successor chain, a retired id falls back to the default, and a
    /// custom id passes through. The seed is migrated the same way.
    /// Stated sensitivity: remove the model migration from `reconciled()` → the
    /// superseded, retired and seed cases go RED.
    @Test
    func writtenModelIdIsTheIdTheNextLaunchLoads() throws {
        let cases: [(written: String, expected: String)] = [
            ("openai/gpt-5.6-luna", "openai/gpt-6-luna"),
            ("google/gemini-2.5-flash-lite", Config.defaultOpenRouterModel),
            ("vendor/custom-model", "vendor/custom-model"),
        ]
        for entry in cases {
            let store = AppStore(state: AppState(config: Config(openRouterModel: "vendor/start-model"), isOpenRouterKeyPresent: true))
            store.update { $0.config.openRouterModel = entry.written }
            #expect(store.state.config.openRouterModel == entry.expected, "\(entry.written) in the store")
            #expect(store.state.effectiveCleanupConfig.model == entry.expected, "\(entry.written) at the orchestrator")
            let defaults = FakeUserDefaults()
            try ConfigStore.save(store.state.config, to: defaults)
            #expect(ConfigStore.load(from: defaults).openRouterModel == entry.expected, "\(entry.written) after relaunch")
        }
        let seeded = AppStore(state: AppState(config: Config(openRouterModel: "openai/gpt-5.4-nano"), isOpenRouterKeyPresent: true))
        #expect(seeded.state.config.openRouterModel == "openai/gpt-6-luna")
    }
}
