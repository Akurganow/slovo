import Synchronization
import Testing

import SlovoCore
import SlovoTestSupport

// Each effect of AppState is a subscriber wired in SlovoCore. Every test wires a
// store to fake targets, changes one slice, and observes the target, through a
// real orchestrator wherever the effect reaches one.
@Suite("App store effects")
@MainActor
struct AppStoreEffectsTests {
    private static let vocabulary = [Term(term: "ExampleCorp", expansion: nil, lang: .en, weight: 9)]

    private static func makeStore() -> AppStore {
        AppStore(state: AppState(config: Config(), isOpenRouterKeyPresent: true))
    }

    private static func targets(
        defaults: FakeUserDefaults = FakeUserDefaults(),
        orchestrator: Orchestrator? = nil,
        reconfigureHotkeys: @escaping (HotkeyConfiguration) -> Void = { _ in },
        cueController: (any DictationCueController)? = nil,
        updaterSwitch: (any UpdaterSwitch)? = nil,
        updateInputDevice: @escaping (InputDevice?) -> Void = { _ in },
        fetchScopeIds: @escaping @Sendable () async throws -> Set<String> = { [] }
    ) -> AppStoreEffectTargets {
        AppStoreEffectTargets(
            defaults: defaults,
            orchestrator: { orchestrator },
            reconfigureHotkeys: reconfigureHotkeys,
            cueController: { cueController },
            updaterSwitch: { updaterSwitch },
            updateInputDevice: updateInputDevice,
            fetchScopeIds: fetchScopeIds
        )
    }

    /// An orchestrator seeded from the store the way `AppComposition.makeLive` seeds one.
    private static func makeOrchestrator(
        store: AppStore,
        transcriber: any Transcriber = FakeTranscriber(outcome: .success("raw words")),
        cleaner: FakeCleaner = FakeCleaner(outcome: .success("CLEANED")),
        audio: FakeSystemAudioController = FakeSystemAudioController(
            muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
        )
    ) -> Orchestrator {
        PipelineFactory.makeOrchestrator(
            config: store.state.config,
            dependencies: Dependencies(
                transcriber: transcriber,
                cleaner: cleaner,
                injector: FakeInjector(outcome: .success),
                personalization: FakePersonalizationSource(terms: vocabulary),
                audio: audio,
                recorder: FakeAudioRecorder(authorizer: FakeMicrophoneAuthorizer(authorized: true)),
                cueController: FakeDictationCueController(),
                log: RedactionSafeLog(subsystem: "slovo", category: "store-effects-test")
            ),
            cleanupConfig: store.state.effectiveCleanupConfig
        )
    }

    /// A hold that outlasts the readiness cue, which is when muting happens.
    private static func runDictation(on orchestrator: Orchestrator) async {
        await orchestrator.handle(.startRequested)
        await orchestrator.awaitReadinessCue()
        await orchestrator.handle(.stopRequested(.plain))
        await orchestrator.awaitPipelineDrain()
    }

    /// Stated sensitivity: `subscribe` instead of `listen` for the persistence
    /// subscriber → RED.
    @Test
    func configChangeIsSavedAndLaunchIsNot() {
        let defaults = FakeUserDefaults()
        let store = Self.makeStore()
        AppStoreEffects.wire(store, to: Self.targets(defaults: defaults))
        #expect(defaults.data(forKey: ConfigStore.defaultKey) == nil, "wiring must not save the loaded config")
        store.update { $0.config.writingStyle = .formal }
        #expect(ConfigStore.load(from: defaults).writingStyle == .formal)
    }

    /// Stated sensitivity: drop the cleanup listener → RED.
    @Test
    func cleanupConfigReachesTheOrchestrator() async {
        let store = Self.makeStore()
        let cleaner = FakeCleaner(outcome: .success("CLEANED"))
        let orchestrator = Self.makeOrchestrator(store: store, cleaner: cleaner)
        AppStoreEffects.wire(store, to: Self.targets(orchestrator: orchestrator))
        let chosen = "anthropic/claude-haiku-5.5"
        store.update { $0.config.openRouterModel = chosen }
        await settle(orchestrator)
        await Self.runDictation(on: orchestrator)
        #expect(store.state.effectiveCleanupConfig.model == chosen)
        #expect(cleaner.calls.last?.config.model == chosen, "the next dictation must clean with the effective model")
    }

    /// Stated sensitivity: drop either the mute or the vocabulary-bias listener → RED.
    @Test
    func muteAndBiasReachTheOrchestrator() async {
        let store = Self.makeStore()
        let transcriber = FakeTranscriber(outcome: .success("raw words"))
        let audio = FakeSystemAudioController(
            muteReturns: PriorAudioState(deviceID: 42, method: .mute, wasAlreadyMuted: false, priorVolumeScalar: nil)
        )
        let orchestrator = Self.makeOrchestrator(store: store, transcriber: transcriber, audio: audio)
        AppStoreEffects.wire(store, to: Self.targets(orchestrator: orchestrator))

        store.update { $0.config.mutesSystemAudioWhileDictating = false }
        await settle(orchestrator)
        await Self.runDictation(on: orchestrator)
        #expect(audio.muteCount == 0, "the dictation after switching mute off must not mute")

        store.update { $0.config.usesVocabularyBias = true }
        await settle(orchestrator)
        await Self.runDictation(on: orchestrator)
        #expect(transcriber.calls.last?.biasTerms.map(\.term) == ["ExampleCorp"],
                "the dictation after switching bias on must hand the recognizer the vocabulary")
    }

    /// Stated sensitivity: drop the recognition-language listener → RED.
    @Test
    func recognitionLanguageReachesTheTranscriber() async {
        let store = Self.makeStore()
        let engine = FakeSpeechEngine(finalize: .success("raw words"))
        let orchestrator = Self.makeOrchestrator(
            store: store,
            transcriber: TranscriberFixtures.makeTranscriber(engine: engine, keepWarmSeconds: nil)
        )
        AppStoreEffects.wire(store, to: Self.targets(orchestrator: orchestrator))
        store.update { $0.config.language = .ru }
        await settle(orchestrator)
        await Self.runDictation(on: orchestrator)
        #expect(engine.sessionLanguages.last == .ru, "the next session must decode the language the store holds")
    }

    /// Stated sensitivity: drop the hotkey listener → RED.
    @Test
    func hotkeyChangeReconfiguresTheTap() {
        let store = Self.makeStore()
        var received: [HotkeyConfiguration] = []
        AppStoreEffects.wire(store, to: Self.targets(reconfigureHotkeys: { received.append($0) }))
        store.update { $0.config.trigger = .rightCommand }
        #expect(received == [store.state.config.hotkeyConfiguration], "the tap must receive the new keys once")
    }

    /// The recorder reads the preference at its next start, so a choice must reach it
    /// without a pipeline rebuild.
    /// Stated sensitivity: drop the listener, or key it on another field → RED.
    @Test
    func inputDeviceChangeReachesTheRecorder() {
        let store = Self.makeStore()
        var received: [InputDevice?] = []
        AppStoreEffects.wire(store, to: Self.targets(updateInputDevice: { received.append($0) }))
        let interface = InputDevice(uid: "example-uid-1", name: "Example Interface")
        store.update { $0.config.preferredInputDevice = interface }
        #expect(received == [interface], "the recorder must receive the new preference once")
    }

    /// The controller snapshots the preference at key-down, so the update must land
    /// before `update` returns.
    /// Stated sensitivity: wrap the controller call in a `Task` → RED.
    @Test
    func soundCueChangeUpdatesTheControllerSynchronously() {
        let store = Self.makeStore()
        let cues = FakeDictationCueController()
        AppStoreEffects.wire(store, to: Self.targets(cueController: cues))
        store.update { $0.config.playsDictationSoundCues = false }
        #expect(cues.events == [.updateEnabled(false)])
    }

    /// Stated sensitivity: drop the updater listener → RED.
    @Test
    func automaticUpdatesChangeDrivesTheSwitch() {
        let store = Self.makeStore()
        let updater = FakeUpdaterSwitch()
        AppStoreEffects.wire(store, to: Self.targets(updaterSwitch: updater))
        store.update { $0.config.automaticallyInstallsUpdates = false }
        #expect(updater.assignments == [false])
    }

    /// One fetch per pending generation. While a fetch is in flight, a second 404 and
    /// an unrelated write start no second fetch: `pendingFetch` keeps its value, so
    /// the slice comparison holds the subscriber back. The fetched ids exclude the
    /// stored preference, and folding them leaves `config` unchanged (K1).
    /// Stated sensitivity: drop the fetch subscriber, skip `.fetchCompleted`, deliver
    /// without the slice comparison, or write `config` in the fetch subscriber → RED.
    @Test
    func pendingFetchRunsOneFetchAndFoldsTheResult() async {
        let ids: Set<String> = ["anthropic/claude-haiku-5.5"]
        let fetches = Mutex(0)
        let gate = FetchGate()
        let store = Self.makeStore()
        AppStoreEffects.wire(store, to: Self.targets(fetchScopeIds: {
            fetches.withLock { $0 += 1 }
            await gate.wait()
            return ids
        }))
        store.update { $0.applyScope(.pipelineStarted) }
        #expect(await waitUntil { fetches.withLock { $0 } == 1 })
        store.update { $0.applyScope(.cleanupFailed(.apiError(status: 404))) }
        store.update { $0.config.writingStyle = .formal }
        let configBeforeFold = store.state.config
        await gate.open()
        #expect(await waitUntil { store.state.cleanupScope.scope == .known(ids) })
        #expect(fetches.withLock { $0 } == 1, "a 404 while a fetch is in flight must start no second fetch")
        #expect(store.state.config == configBeforeFold, "ids that exclude the preference must not rewrite it (K1)")
        store.update { $0.applyScope(.keySaved) }
        #expect(await waitUntil { fetches.withLock { $0 } == 2 && store.state.cleanupScope.scope == .known(ids) })
        #expect(fetches.withLock { $0 } == 2, "one fetch per pending generation")
    }

    /// Stated sensitivity: `listen` instead of `subscribe` for the fetch subscriber → RED.
    @Test
    func aFetchPendingAtWireTimeRunsOnce() async {
        let ids: Set<String> = ["anthropic/claude-haiku-5.5"]
        let fetches = Mutex(0)
        let store = Self.makeStore()
        store.update { $0.applyScope(.pipelineStarted) }
        #expect(store.state.pendingFetch != nil)
        AppStoreEffects.wire(store, to: Self.targets(fetchScopeIds: {
            fetches.withLock { $0 += 1 }
            return ids
        }))
        #expect(await waitUntil { store.state.cleanupScope.scope == .known(ids) })
        #expect(fetches.withLock { $0 } == 1)
    }
}

/// Holds every fake fetch until the test opens it, so a fetch stays in flight while
/// the test writes to the store.
private actor FetchGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}
