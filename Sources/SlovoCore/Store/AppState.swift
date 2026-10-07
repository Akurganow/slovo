/// The app's state as one value: the persisted `Config`, the mirrors the app
/// keeps of the Keychain, the key's model scope and the vocabulary table, and
/// the runtime state the status menu and the Settings window read.
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
    /// The present input devices and the system default input. Read once at launch,
    /// then on each menu open and each device-list or default-input change. Not in
    /// `menuStructure`: the Microphone submenu's row listener updates it in place.
    public var inputDevices = InputDevices()
    public var updateIndication: UpdateIndication = .idle
    /// The pane Settings… opens: the last one the user viewed, About excepted.
    /// General until the first visit, and again after a relaunch.
    /// `recordSettingsPane`, in this file, is its only writer.
    public private(set) var lastSettingsPane: SettingsPaneID = .general

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

    /// Records the pane the Settings toolbar selects. About, and nil (no selection,
    /// or an identifier that names no pane), record nothing, so Settings… never
    /// opens on About.
    public mutating func recordSettingsPane(_ pane: SettingsPaneID?) {
        guard let pane, pane != .about else { return }
        lastSettingsPane = pane
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

    var inputDeviceChoice: InputDeviceChoice {
        InputDeviceChoice.derive(preference: config.preferredInputDevice, devices: inputDevices)
    }

    var menuStructure: MenuStructure {
        MenuStructure(mode: menuMode, input: dictationMenuInput)
    }

    var statusLineText: String {
        statusLine.text(idleTrigger: config.trigger)
    }
}

/// The configuration values the dictation menu is built from. The menu rebuilds
/// when these or the menu mode change; the status, fn and update rows, the mute
/// item's availability and the Microphone submenu follow state through their own
/// listeners.
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

/// The Settings window's panes, in toolbar order: the app builds the toolbar from
/// `allCases`. A raw value is the pane's identifier string in the Settings package.
public enum SettingsPaneID: String, CaseIterable, Sendable {
    case general, cleanup, vocabulary, about
}

/// What a menu build depends on. The status, fn and update rows, the mute item's
/// availability and the Microphone submenu are not in it: their listeners update
/// them in place, so a change to one never rebuilds the menu.
public struct MenuStructure: Equatable, Sendable {
    public let mode: MenuMode
    public let input: DictationMenuInput
}
