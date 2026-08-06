/// A key that can drive a hold — either as the push-to-talk key (`fn` by default,
/// so existing installs are untouched) or as the translate key. The sided entries
/// name ONE physical key: the left or the right ⌘, ⌥ or ⇧. A single side is rarely
/// pressed alone, so it collides minimally with normal typing, and binding the
/// whole modifier class instead would make the opposite side's ordinary shortcuts
/// start dictating. Control is the exception, offered as a single class-level
/// entry — either Control key matches — because most Mac laptop keyboards have no
/// right Control key to distinguish. Declaration order is picker order.
public enum HotkeyTrigger: String, CaseIterable, Equatable, Sendable {
    case fn = "fn"
    case leftCommand = "left-command"
    case rightCommand = "right-command"
    case leftOption = "left-option"
    // Wire compatibility: these bytes predate the side split and keep their
    // original right-only meaning, so an install that stored them still loads.
    // Older builds fail the whole config closed on an unknown trigger, so the
    // stored string must never change.
    case rightOption = "right-option"
    case leftShift = "left-shift"
    case rightShift = "right-shift"
    case control = "control"

    /// Human-readable name for the status line and the Settings picker.
    public var displayName: String {
        switch self {
        case .fn: return "fn"
        case .leftCommand: return "Left ⌘"
        case .rightCommand: return "Right ⌘"
        case .leftOption: return "Left ⌥"
        case .rightOption: return "Right ⌥"
        case .leftShift: return "Left ⇧"
        case .rightShift: return "Right ⇧"
        // No side word: this one entry stands for both Control keys.
        case .control: return "⌃"
        }
    }
}

/// User-editable app configuration persisted as JSON.
public struct Config: Equatable, Sendable {
    public static let defaultTrigger: HotkeyTrigger = .fn
    public static let defaultTranslateTrigger: HotkeyTrigger = .control
    public static let defaultMode = "hold"
    public static let defaultAsrModel = "large-v3-v20240930_turbo_632MB"
    public static let defaultOpenRouterModel = CleanupDefaults.openRouterModel

    public static let defaults = Config()

    public var language: Language
    /// WhisperKit model retention: `nil` keeps the model resident by default
    /// (fastest first word), `0` releases immediately after each dictation, a
    /// positive value is the idle-seconds window before release.
    public var keepWarmSeconds: Int?
    public var trigger: HotkeyTrigger
    /// The key that makes a dictation translate. Must differ from `trigger`:
    /// `ConfigStore` is where that exclusion is enforced, failing a colliding pair
    /// closed rather than persisting or loading it.
    public var translateTrigger: HotkeyTrigger
    /// Whether the translate key rides ON TOP of a `trigger` hold — the default,
    /// and exactly what holding Control did before the key became configurable —
    /// rather than opening a translate dictation of its own.
    public var translateKeyIsAdditional: Bool
    public var asrBackend: AsrBackend
    public var asrModel: String
    public var openRouterModel: String
    /// Whether the cleanup step runs at all — the user's stored PREFERENCE.
    /// The per-session EFFECTIVE value also requires an OpenRouter key; see
    /// `CleanupAvailability` (app layer) and `CleanupConfig.runsCleaner`.
    public var cleanupEnabled: Bool
    public var writingStyle: WritingStyle
    /// Advisory spell-check hints for cleanup, default on (spec Workstream 3). The
    /// input-language hint has no toggle; only the spell pass does.
    public var useSpellCheckHints: Bool
    /// Whether Slovo mutes system audio output while the push-to-talk key is held,
    /// default on (today's unconditional-mute behavior). A capture-stage setting, so
    /// it is not part of `cleanupConfig`.
    public var mutesSystemAudioWhileDictating: Bool
    /// Whether dictation boundaries and failures use audible system-alert cues.
    /// The system alert volume owns loudness; Slovo has no separate volume value.
    public var playsDictationSoundCues: Bool
    /// The persisted target language a translate pass renders into; read only in
    /// translate mode. Config never yields `translate = true`.
    public var translationTargetLanguage: Language
    /// Whether Slovo automatically installs updates (hourly background check,
    /// silent download, install-on-quit), default on. Off makes zero
    /// update-related network requests.
    public var automaticallyInstallsUpdates: Bool

    public var cleanupConfig: CleanupConfig {
        CleanupConfig(
            model: cleanupModel,
            writingStyle: writingStyle,
            language: language,
            useSpellCheckHints: useSpellCheckHints,
            translationTargetLanguage: translationTargetLanguage,
            // Preference only — the key fact joins in the app layer.
            runsCleaner: cleanupEnabled
        )
    }

    public var cleanupModel: String {
        openRouterModel
    }

    /// The Hotkey layer's view of the configured keys. The two are already known to
    /// differ (`ConfigStore` validation), so the projection only names their roles.
    public var hotkeyConfiguration: HotkeyConfiguration {
        HotkeyConfiguration(
            main: trigger,
            translate: translateTrigger,
            translateIsAdditional: translateKeyIsAdditional
        )
    }

    public init(
        language: Language = .auto,
        keepWarmSeconds: Int? = nil,
        trigger: HotkeyTrigger = Config.defaultTrigger,
        translateTrigger: HotkeyTrigger = Config.defaultTranslateTrigger,
        translateKeyIsAdditional: Bool = true,
        asrBackend: AsrBackend = .whisperKit,
        asrModel: String = Config.defaultAsrModel,
        openRouterModel: String = Config.defaultOpenRouterModel,
        cleanupEnabled: Bool = true,
        writingStyle: WritingStyle = .casual,
        useSpellCheckHints: Bool = true,
        mutesSystemAudioWhileDictating: Bool = true,
        playsDictationSoundCues: Bool = true,
        translationTargetLanguage: Language = .en,
        automaticallyInstallsUpdates: Bool = true
    ) {
        self.language = language
        self.keepWarmSeconds = keepWarmSeconds
        self.trigger = trigger
        self.translateTrigger = translateTrigger
        self.translateKeyIsAdditional = translateKeyIsAdditional
        self.asrBackend = asrBackend
        self.asrModel = asrModel
        self.openRouterModel = openRouterModel
        self.cleanupEnabled = cleanupEnabled
        self.writingStyle = writingStyle
        self.useSpellCheckHints = useSpellCheckHints
        self.mutesSystemAudioWhileDictating = mutesSystemAudioWhileDictating
        self.playsDictationSoundCues = playsDictationSoundCues
        self.translationTargetLanguage = translationTargetLanguage
        self.automaticallyInstallsUpdates = automaticallyInstallsUpdates
    }
}
