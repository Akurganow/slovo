/// The app's state as one value: the persisted `Config`, the mirrors the app
/// keeps of the Keychain, the key's model scope and the vocabulary table, and
/// the runtime state the status menu shows.
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
    public var menuMode: MenuMode = .dictation
    public var statusLine: StatusLine = .idle
    /// Whether macOS also claims the fn key; read from the system on each menu open.
    public var isFnKeySystemAssigned: Bool
    /// Whether the default output device can be muted. Re-read on each menu open and
    /// on each default-output change. Not in `menuStructure`: the mute item's row
    /// listener updates it in place. The default is never shown, because Settings
    /// opens only from the dropdown, whose open re-reads this.
    public var outputMuteAvailability: OutputMuteAvailability = .available
    public var updateIndication: UpdateIndication = .idle

    public init(
        config: Config,
        isOpenRouterKeyPresent: Bool,
        vocabulary: [VocabularyRecord] = [],
        isFnKeySystemAssigned: Bool = false
    ) {
        self.config = config
        self.isOpenRouterKeyPresent = isOpenRouterKeyPresent
        self.vocabulary = vocabulary
        self.isFnKeySystemAssigned = isFnKeySystemAssigned
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

    var menuStructure: MenuStructure {
        MenuStructure(mode: menuMode, input: dictationMenuInput)
    }

    var statusLineText: String {
        statusLine.text(idleTrigger: config.trigger)
    }
}

/// The configuration values the dictation menu is built from. The menu rebuilds
/// when these or the menu mode change; the status, fn and update rows and the
/// mute item's availability follow state through their own listeners.
public struct DictationMenuInput: Equatable, Sendable {
    public let hotkeyConfiguration: HotkeyConfiguration
    public let cleanupModelSelection: CleanupModelSelection.Result
    public let translationTargetLanguage: Language
    public let cleanupAvailability: CleanupAvailability
    public let mutesSystemAudioWhileDictating: Bool
    public let playsDictationSoundCues: Bool
}

/// Which menu the status item shows. Runtime UI state, never persisted.
public enum MenuMode: Equatable, Sendable {
    case dictation
    /// First-run setup, with the permission steps still pending.
    case onboarding([OnboardingStep])
    case hotkeyRecovery

    public var isOnboarding: Bool {
        if case .onboarding = self { return true }
        return false
    }
}

/// What a menu build depends on. The status, fn and update rows and the mute item's
/// availability are not in it: their listeners update them in place, so a change to
/// one never rebuilds the menu.
public struct MenuStructure: Equatable, Sendable {
    public let mode: MenuMode
    public let input: DictationMenuInput
}
