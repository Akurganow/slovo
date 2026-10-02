/// The app's state as one value: the persisted `Config` and the mirrors the app
/// keeps of the Keychain, the key's model scope and the vocabulary table.
/// `AppStore.update` is its one mutation path. Derived values are the selectors
/// below, each a call into an existing pure function.
public struct AppState: Equatable, Sendable {
    public var config: Config
    /// Mirrors `hasConfiguredKey()`; the Keychain stays the source of truth.
    public var isOpenRouterKeyPresent: Bool
    /// `private(set)` leaves `applyScope`, in this file, its only writer.
    public private(set) var cleanupScope = CleanupScopeState()
    /// Mirrors the SQLite vocabulary table; the table stays the source of truth.
    public var vocabulary: [VocabularyRecord]

    public init(config: Config, isOpenRouterKeyPresent: Bool, vocabulary: [VocabularyRecord] = []) {
        self.config = config
        self.isOpenRouterKeyPresent = isOpenRouterKeyPresent
        self.vocabulary = vocabulary
    }
}

extension AppState {
    /// Applies one scope event. The only writer of `cleanupScope`.
    public mutating func applyScope(_ event: CleanupScopeEvent) {
        cleanupScope = CleanupScopeReducer.reduce(cleanupScope, event)
    }

    /// Migrates the model id as `ConfigStore.load` does, so an id written live is the
    /// id the next launch loads, and feeds the availability edge, so
    /// `cleanupIsOn == cleanupAvailability.isOn`.
    func reconciled() -> AppState {
        var next = self
        next.config.openRouterModel = ConfigStore.migratedOpenRouterModel(next.config.openRouterModel)
        next.applyScope(.availabilityChanged(isOn: next.cleanupAvailability.isOn))
        return next
    }
}

public extension AppState {
    var cleanupAvailability: CleanupAvailability {
        CleanupAvailability.derive(preference: config.cleanupEnabled, keyPresent: isOpenRouterKeyPresent)
    }

    var cleanupModelSelection: CleanupModelSelection.Result {
        CleanupModelSelection.derive(
            preference: config.openRouterModel,
            catalog: CleanupModelCatalog.options,
            scope: cleanupScope.scope
        )
    }

    /// What the orchestrator runs: the derived model and the effective on/off.
    var effectiveCleanupConfig: CleanupConfig {
        var cleanupConfig = config.cleanupConfig
        cleanupConfig.model = cleanupModelSelection.effective
        cleanupConfig.runsCleaner = cleanupAvailability.isOn
        return cleanupConfig
    }

    /// The generation a scope fetch must run for, or nil while none is pending.
    var pendingFetch: Int? {
        cleanupScope.fetchInFlight ? cleanupScope.generation : nil
    }

    var dictationMenuInput: DictationMenuInput {
        DictationMenuInput(
            hotkeyConfiguration: config.hotkeyConfiguration,
            cleanupModelSelection: cleanupModelSelection,
            translationTargetLanguage: config.translationTargetLanguage,
            cleanupAvailability: cleanupAvailability,
            mutesSystemAudioWhileDictating: config.mutesSystemAudioWhileDictating,
            playsDictationSoundCues: config.playsDictationSoundCues
        )
    }
}

/// Every value the dictation menu shows, and nothing else: the menu rebuilds
/// when this changes and only then.
public struct DictationMenuInput: Equatable, Sendable {
    public let hotkeyConfiguration: HotkeyConfiguration
    public let cleanupModelSelection: CleanupModelSelection.Result
    public let translationTargetLanguage: Language
    public let cleanupAvailability: CleanupAvailability
    public let mutesSystemAudioWhileDictating: Bool
    public let playsDictationSoundCues: Bool
}
