/// The push-to-talk trigger key. `fn` is the default (existing installs are
/// untouched); ⌘, ⌃ and ⇧ bind the RIGHT side only, because a side-specific
/// modifier is rarely pressed alone and so collides minimally with normal typing.
/// ⌥ is the exception by owner decision — it matches either side, and the
/// interrupt-cancel path (any key pressed mid-hold cancels silently) keeps the
/// wider match from disturbing normal typing.
public enum HotkeyTrigger: String, CaseIterable, Equatable, Sendable {
    case fn = "fn"
    case rightCommand = "right-command"
    // Wire compatibility: the stored string predates the either-side widening and
    // must never change — older builds fail the whole config closed on an unknown
    // trigger value, so a rename here would reset a downgraded install's settings.
    case option = "right-option"
    case rightControl = "right-control"
    case rightShift = "right-shift"

    /// Human-readable name for the menu hint and the Settings picker.
    public var displayName: String {
        switch self {
        case .fn: return "fn"
        case .rightCommand: return "Right ⌘"
        case .option: return "⌥ Option"
        case .rightControl: return "Right ⌃"
        case .rightShift: return "Right ⇧"
        }
    }
}

/// User-editable app configuration persisted as JSON.
public struct Config: Equatable, Sendable {
    public static let defaultTrigger: HotkeyTrigger = .fn
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

    public init(
        language: Language = .auto,
        keepWarmSeconds: Int? = nil,
        trigger: HotkeyTrigger = Config.defaultTrigger,
        asrBackend: AsrBackend = .whisperKit,
        asrModel: String = Config.defaultAsrModel,
        openRouterModel: String = Config.defaultOpenRouterModel,
        cleanupEnabled: Bool = true,
        writingStyle: WritingStyle = .casual,
        useSpellCheckHints: Bool = true,
        mutesSystemAudioWhileDictating: Bool = true,
        translationTargetLanguage: Language = .en,
        automaticallyInstallsUpdates: Bool = true
    ) {
        self.language = language
        self.keepWarmSeconds = keepWarmSeconds
        self.trigger = trigger
        self.asrBackend = asrBackend
        self.asrModel = asrModel
        self.openRouterModel = openRouterModel
        self.cleanupEnabled = cleanupEnabled
        self.writingStyle = writingStyle
        self.useSpellCheckHints = useSpellCheckHints
        self.mutesSystemAudioWhileDictating = mutesSystemAudioWhileDictating
        self.translationTargetLanguage = translationTargetLanguage
        self.automaticallyInstallsUpdates = automaticallyInstallsUpdates
    }
}
