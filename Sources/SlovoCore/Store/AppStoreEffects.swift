import os

/// Where `AppState`'s effects land. Closures and SlovoCore types only, so the
/// wiring stays in SlovoCore and cannot rebuild the pipeline: only the app target
/// can call `retrySetup` or `startPipeline`.
@preconcurrency // required by the strict SwiftLint rule incompatible_concurrency_annotation
@MainActor
public struct AppStoreEffectTargets {
    public var defaults: any UserDefaultsWriting
    public var orchestrator: () -> Orchestrator?
    public var reconfigureHotkeys: (HotkeyConfiguration) -> Void
    public var cueController: () -> (any DictationCueController)?
    public var updaterSwitch: () -> (any UpdaterSwitch)?
    public var fetchScopeIds: @Sendable () async throws -> Set<String>

    @preconcurrency // required by the strict SwiftLint rule incompatible_concurrency_annotation
    public init(
        defaults: any UserDefaultsWriting,
        orchestrator: @escaping () -> Orchestrator?,
        reconfigureHotkeys: @escaping (HotkeyConfiguration) -> Void,
        cueController: @escaping () -> (any DictationCueController)?,
        updaterSwitch: @escaping () -> (any UpdaterSwitch)?,
        fetchScopeIds: @escaping @Sendable () async throws -> Set<String>
    ) {
        self.defaults = defaults
        self.orchestrator = orchestrator
        self.reconfigureHotkeys = reconfigureHotkeys
        self.cueController = cueController
        self.updaterSwitch = updaterSwitch
        self.fetchScopeIds = fetchScopeIds
    }
}

/// Every effect that is a function of `AppState`, each a subscriber on the slice
/// it projects. No subscriber writes to the store while it is being notified; the
/// fetch writes later, when its task completes.
public enum AppStoreEffects {
    private static let log = Logger(subsystem: "com.slovo.app", category: "store")

    @preconcurrency // required by the strict SwiftLint rule incompatible_concurrency_annotation
    @MainActor
    public static func wire(_ store: AppStore, to targets: AppStoreEffectTargets) {
        // `listen`, never `subscribe`: a save at wire time would overwrite an
        // invalid stored blob that `ConfigStore.load` failed closed on.
        store.listen(\.config) { config in
            do {
                try ConfigStore.save(config, to: targets.defaults)
            } catch {
                log.error("config save failed")
            }
        }
        // Each push reads the orchestrator when the value changes, so a push made
        // before a pipeline rebuild reaches the orchestrator it was computed for.
        store.listen(\.effectiveCleanupConfig) { config in
            let orchestrator = targets.orchestrator()
            Task { await orchestrator?.updateCleanupConfig(config) }
        }
        store.listen(\.config.mutesSystemAudioWhileDictating) { isOn in
            let orchestrator = targets.orchestrator()
            Task { await orchestrator?.updateMutesSystemAudioWhileDictating(isOn) }
        }
        store.listen(\.config.usesVocabularyBias) { isOn in
            let orchestrator = targets.orchestrator()
            Task { await orchestrator?.updateUsesVocabularyBias(isOn) }
        }
        store.listen(\.config.language) { language in
            let orchestrator = targets.orchestrator()
            Task { await orchestrator?.updateRecognitionLanguage(language) }
        }
        store.listen(\.config.hotkeyConfiguration) { targets.reconfigureHotkeys($0) }
        // Synchronous: the controller snapshots the preference at the next key-down.
        store.listen(\.config.playsDictationSoundCues) { targets.cueController()?.updateEnabled($0) }
        store.listen(\.config.automaticallyInstallsUpdates) { isOn in
            guard let updater = targets.updaterSwitch() else { return }
            UpdaterActivation.apply(automaticUpdatesEnabled: isOn, to: updater)
        }
        // `subscribe`, so a fetch already pending at wire time still runs.
        store.subscribe(\.pendingFetch) { [weak store] generation in
            guard let generation, let store else { return }
            let fetch = targets.fetchScopeIds
            Task { @MainActor in
                let ids = try? await fetch()
                store.update { $0.applyScope(.fetchCompleted(generation: generation, ids: ids)) }
            }
        }
    }
}
