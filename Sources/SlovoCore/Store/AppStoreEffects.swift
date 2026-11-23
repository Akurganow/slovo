import os

/// Where `AppState`'s effects land. Closures and SlovoCore types only, so the
/// wiring stays in SlovoCore and cannot rebuild the pipeline: only the app target
/// can call `retrySetup` or `startPipeline`.
@preconcurrency // required by the strict SwiftLint rule incompatible_concurrency_annotation
@MainActor
public struct AppStoreEffectTargets {
    public var defaults: any UserDefaultsWriting
    public var reconfigureHotkeys: (HotkeyConfiguration) -> Void
    public var cueController: () -> (any DictationCueController)?
    public var updaterSwitch: () -> (any UpdaterSwitch)?
    public var updateInputDevice: (InputDevice?) -> Void
    public var fetchScopeIds: @Sendable () async throws -> Set<String>

    @preconcurrency // required by the strict SwiftLint rule incompatible_concurrency_annotation
    public init(
        defaults: any UserDefaultsWriting,
        reconfigureHotkeys: @escaping (HotkeyConfiguration) -> Void,
        cueController: @escaping () -> (any DictationCueController)?,
        updaterSwitch: @escaping () -> (any UpdaterSwitch)?,
        updateInputDevice: @escaping (InputDevice?) -> Void,
        fetchScopeIds: @escaping @Sendable () async throws -> Set<String>
    ) {
        self.defaults = defaults
        self.reconfigureHotkeys = reconfigureHotkeys
        self.cueController = cueController
        self.updaterSwitch = updaterSwitch
        self.updateInputDevice = updateInputDevice
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
        // `listen`, never `subscribe`: a save at wire time would overwrite the stored
        // blob with its recovered form before any setting changed.
        store.listen(\.config) { config in
            do {
                try ConfigStore.save(config, to: targets.defaults)
            } catch {
                log.error("config save failed")
            }
        }
        store.listen(\.config.hotkeyConfiguration) { targets.reconfigureHotkeys($0) }
        // Synchronous: the controller snapshots the preference at the next key-down.
        store.listen(\.config.playsDictationSoundCues) { targets.cueController()?.updateEnabled($0) }
        // `listen`: the recorder is built from state. It reads the preference at its
        // next start.
        store.listen(\.config.preferredInputDevice) { targets.updateInputDevice($0) }
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
