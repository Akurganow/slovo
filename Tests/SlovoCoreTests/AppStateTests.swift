import Testing

import SlovoCore

// The selectors over AppState and the reconcile that keeps the scope reducer's
// edge memory equal to cleanup availability in every committed state.
@Suite("App state")
struct AppStateTests {
    private static func makeState(cleanupEnabled: Bool = true, keyPresent: Bool = true) -> AppState {
        var config = Config()
        config.cleanupEnabled = cleanupEnabled
        return AppState(config: config, isOpenRouterKeyPresent: keyPresent)
    }

    /// The launch sequence: the seed's availability edge, then hotkey start. It
    /// leaves the first scope fetch pending.
    private static func launched() -> AppState {
        var state = makeState()
        state.applyScope(.availabilityChanged(isOn: true))
        state.applyScope(.pipelineStarted)
        return state
    }

    /// Stated sensitivity: pass `true` for `keyPresent` in the selector → RED.
    @Test
    func availabilityRequiresTheKey() {
        #expect(Self.makeState(keyPresent: false).cleanupAvailability == .offNoKey)
        #expect(Self.makeState(keyPresent: true).cleanupAvailability == .on)
    }

    /// Stated sensitivity: use `config.openRouterModel` for `model`, or
    /// `config.cleanupEnabled` for `runsCleaner` → RED.
    @Test
    func effectiveCleanupConfigUsesTheDerivedModelAndAvailability() throws {
        let other = try #require(CleanupModelCatalog.options.first { $0.id != Config.defaultOpenRouterModel })
        var state = Self.launched()
        state.applyScope(.fetchCompleted(generation: state.cleanupScope.generation, ids: [other.id]))
        try #require(state.cleanupModelSelection.effective != state.config.openRouterModel,
                     "the known scope must exclude the stored preference")
        #expect(state.effectiveCleanupConfig.model == state.cleanupModelSelection.effective)

        let noKey = Self.makeState(keyPresent: false)
        #expect(noKey.config.cleanupEnabled)
        #expect(!noKey.effectiveCleanupConfig.runsCleaner, "without a key the orchestrator must run raw")
    }

    /// The menu input carries each value the menu shows, read from its own field,
    /// and nothing else: the menu rebuilds when the input changes and only then.
    /// Stated sensitivity: feed any input field from another `Config` field or a
    /// constant → RED; add any unshown field to `DictationMenuInput` → RED.
    @Test
    func menuInputCarriesExactlyTheShownFields() throws {
        let base = Self.makeState()
        let model = try #require(CleanupModelCatalog.options.first { $0.id != base.config.openRouterModel })
        let shown: [(change: (inout AppState) -> Void, holds: (DictationMenuInput) -> Bool)] = [
            ({ $0.config.trigger = .rightOption }, { $0.hotkeyConfiguration.main == .rightOption }),
            ({ $0.config.translateTrigger = .leftShift }, { $0.hotkeyConfiguration.translate == .leftShift }),
            ({ $0.config.translateKeyIsAdditional = false }, { !$0.hotkeyConfiguration.translateIsAdditional }),
            ({ $0.config.openRouterModel = model.id }, { $0.cleanupModelSelection.effective == model.id }),
            ({ state in
                state.applyScope(.availabilityChanged(isOn: true))
                state.applyScope(.pipelineStarted)
                state.applyScope(.fetchCompleted(generation: state.cleanupScope.generation, ids: [model.id]))
            }, { $0.cleanupModelSelection.options == [model] }),
            ({ $0.config.translationTargetLanguage = .ru }, { $0.translationTargetLanguage == .ru }),
            ({ $0.config.cleanupEnabled = false }, { $0.cleanupAvailability == .offByChoice }),
            ({ $0.isOpenRouterKeyPresent = false }, { $0.cleanupAvailability == .offNoKey }),
            ({ $0.config.mutesSystemAudioWhileDictating = false }, { !$0.mutesSystemAudioWhileDictating }),
            ({ $0.config.playsDictationSoundCues = false }, { !$0.playsDictationSoundCues }),
        ]
        for (index, entry) in shown.enumerated() {
            var changed = base
            entry.change(&changed)
            #expect(entry.holds(changed.dictationMenuInput), "shown change \(index) must reach its own menu input field")
        }

        let unshown: [(inout AppState) -> Void] = [
            { $0.config.writingStyle = .formal },
            { $0.config.useSpellCheckHints = false },
            { $0.config.usesVocabularyBias = true },
            { $0.config.language = .ru },
            { $0.config.automaticallyInstallsUpdates = false },
        ]
        for change in unshown {
            var changed = base
            change(&changed)
            #expect(changed != base, "each change must alter the state")
            #expect(changed.dictationMenuInput == base.dictationMenuInput, "a field the menu does not show must not rebuild it")
        }
    }

    /// Stated sensitivity: skip `reconciled()` in `update` or in `init`, or let the
    /// `.availabilityChanged` arm return before it sets `cleanupIsOn` → RED.
    @Test
    @MainActor
    func reconcileKeepsTheScopeEdgeInStep() {
        let store = AppStore(state: Self.makeState())
        let inStep = { store.state.cleanupScope.cleanupIsOn == store.state.cleanupAvailability.isOn }
        #expect(inStep(), "after the seed")
        store.update { $0.config.cleanupEnabled = false }
        #expect(inStep(), "after toggle off")
        store.update { $0.config.cleanupEnabled = true }
        #expect(inStep(), "after toggle on")
        store.update {
            $0.isOpenRouterKeyPresent = false
            $0.applyScope(.keyRemoved)
        }
        #expect(inStep(), "after key removed")
        store.update {
            $0.isOpenRouterKeyPresent = true
            $0.applyScope(.keySaved)
        }
        #expect(inStep(), "after key saved")
    }

    /// Stated sensitivity: return `generation` regardless of `fetchInFlight` → RED.
    @Test
    func pendingFetchFollowsAvailabilityChanged() {
        var state = Self.makeState()
        state.applyScope(.pipelineStarted)
        #expect(state.pendingFetch == nil, "no fetch while cleanup is off")
        state.applyScope(.availabilityChanged(isOn: true))
        #expect(state.pendingFetch == state.cleanupScope.generation)
        state.applyScope(.availabilityChanged(isOn: false))
        #expect(state.pendingFetch == nil)
    }

    /// Stated sensitivity: return `generation` regardless of `fetchInFlight` → RED.
    @Test
    func pendingFetchFollowsPipelineStarted() {
        var state = Self.makeState()
        state.applyScope(.availabilityChanged(isOn: true))
        #expect(state.pendingFetch == nil, "no fetch before hotkey start (K10)")
        state.applyScope(.pipelineStarted)
        #expect(state.pendingFetch == state.cleanupScope.generation)
        state.applyScope(.fetchCompleted(generation: state.cleanupScope.generation, ids: ["a/b"]))
        let known = state.pendingFetch
        state.applyScope(.pipelineStarted)
        #expect(state.pendingFetch == known, "a restart with a known scope fetches nothing")
    }

    /// Stated sensitivity: return `generation` regardless of `fetchInFlight` → RED.
    @Test
    func pendingFetchFollowsKeySaved() {
        var state = Self.launched()
        state.applyScope(.fetchCompleted(generation: state.cleanupScope.generation, ids: ["a/b"]))
        #expect(state.pendingFetch == nil)
        let before = state.cleanupScope.generation
        state.applyScope(.keySaved)
        #expect(state.pendingFetch == before + 1)
    }

    /// Stated sensitivity: return `generation` regardless of `fetchInFlight` → RED.
    @Test
    func pendingFetchFollowsKeyRemoved() {
        var state = Self.launched()
        #expect(state.pendingFetch != nil)
        state.applyScope(.keyRemoved)
        #expect(state.pendingFetch == nil)
    }

    /// Stated sensitivity: return `generation` regardless of `fetchInFlight` → RED.
    @Test
    func pendingFetchFollowsFetchCompleted() {
        var state = Self.launched()
        let stale = state.cleanupScope.generation
        state.applyScope(.keySaved)
        let pending = state.pendingFetch
        #expect(pending != nil)
        state.applyScope(.fetchCompleted(generation: stale, ids: ["old/model"]))
        #expect(state.pendingFetch == pending, "a stale result changes nothing")
        state.applyScope(.fetchCompleted(generation: state.cleanupScope.generation, ids: ["a/b"]))
        #expect(state.pendingFetch == nil)
    }

    /// Stated sensitivity: return `generation` regardless of `fetchInFlight` → RED.
    @Test
    func pendingFetchFollowsCleanupFailed() {
        var state = Self.launched()
        state.applyScope(.fetchCompleted(generation: state.cleanupScope.generation, ids: ["a/b"]))
        let generation = state.cleanupScope.generation
        state.applyScope(.cleanupFailed(.apiError(status: 403)))
        #expect(state.pendingFetch == nil, "only a 404 refreshes the scope")
        state.applyScope(.cleanupFailed(.apiError(status: 404)))
        #expect(state.pendingFetch == generation, "a 404 refetches under the same generation")
    }

    /// K1: the scope machinery never writes the stored preference, even while the
    /// key's scope excludes it and a substitute model is in effect.
    /// Stated sensitivity: write `config.openRouterModel` (for example the effective
    /// id) inside `applyScope` → RED.
    @Test
    func applyScopeNeverWritesConfig() throws {
        let other = try #require(CleanupModelCatalog.options.first { $0.id != Config.defaultOpenRouterModel })
        var known = Self.launched()
        known.applyScope(.fetchCompleted(generation: known.cleanupScope.generation, ids: [other.id]))
        #expect(known.config == Self.launched().config)
        try #require(known.cleanupModelSelection.effective != known.config.openRouterModel,
                     "the known scope must exclude the stored preference")
        let events: [CleanupScopeEvent] = [
            .availabilityChanged(isOn: false), .availabilityChanged(isOn: true), .pipelineStarted,
            .keySaved, .keyRemoved,
            .fetchCompleted(generation: known.cleanupScope.generation, ids: [other.id]),
            .fetchCompleted(generation: known.cleanupScope.generation, ids: nil),
            .cleanupFailed(.apiError(status: 404)), .cleanupFailed(.offline),
        ]
        for event in events {
            var state = known
            state.applyScope(event)
            #expect(state.config == known.config, "\(event) must not write the stored config")
        }
    }

    /// The status row, the fn row and the update row update in place, so none of
    /// them may rebuild the menu.
    /// Stated sensitivity: include any of them in the structure → RED (a rebuild
    /// per status change).
    @Test
    func statusLineChangesLeaveMenuStructureEqual() {
        let base = AppState(config: .defaults, isOpenRouterKeyPresent: false)
        var recording = base
        recording.statusLine = .recording
        var fnAssigned = base
        fnAssigned.isFnKeySystemAssigned.toggle()
        var updateReady = base
        updateReady.updateIndication = .ready(version: "9.9.9")
        #expect(recording.menuStructure == base.menuStructure)
        #expect(fnAssigned.menuStructure == base.menuStructure)
        #expect(updateReady.menuStructure == base.menuStructure)
    }

    /// The installed menu follows the mode, so a mode change must rebuild it.
    /// Stated sensitivity: drop `menuMode` from the structure → RED.
    @Test
    func menuModeChangesMenuStructure() {
        let dictation = AppState(config: .defaults, isOpenRouterKeyPresent: false)
        var onboarding = dictation
        onboarding.menuMode = .onboarding([.requestMicrophone])
        var recovery = dictation
        recovery.menuMode = .hotkeyRecovery
        #expect(onboarding.menuStructure != dictation.menuStructure)
        #expect(recovery.menuStructure != dictation.menuStructure)
    }

    /// The idle line names the main key, never the translate key.
    /// Stated sensitivity: seed the idle line from `config.translateTrigger` → RED.
    @Test
    func statusLineTextUsesTheMainKey() {
        var config = Config.defaults
        config.trigger = .rightCommand
        config.translateTrigger = .control
        let state = AppState(config: config, isOpenRouterKeyPresent: false)
        #expect(state.statusLine == .idle)
        #expect(state.statusLineText == "Hold Right ⌘ to talk")
    }
}
