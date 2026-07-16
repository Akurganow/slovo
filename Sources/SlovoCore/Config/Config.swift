/// The push-to-talk trigger key. `fn` is the default (existing installs are
/// untouched); the right-hand modifiers are rarely pressed alone, so binding one
/// as push-to-talk collides minimally with normal typing.
public enum HotkeyTrigger: String, CaseIterable, Equatable, Sendable {
    case fn = "fn"
    case rightCommand = "right-command"
    case rightOption = "right-option"
    case rightControl = "right-control"
    case rightShift = "right-shift"

    /// Human-readable name for the menu hint and the Settings picker.
    public var displayName: String {
        switch self {
        case .fn: return "fn"
        case .rightCommand: return "Right ⌘"
        case .rightOption: return "Right ⌥"
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
    public var writingStyle: WritingStyle
    /// Advisory spell-check hints for cleanup, default on (spec Workstream 3). The
    /// input-language hint has no toggle; only the spell pass does.
    public var useSpellCheckHints: Bool
    /// Whether Slovo mutes system audio output while the push-to-talk key is held,
    /// default on (today's unconditional-mute behavior). A capture-stage setting, so
    /// it is not part of `cleanupConfig`.
    public var mutesSystemAudioWhileDictating: Bool

    public var cleanupConfig: CleanupConfig {
        CleanupConfig(
            model: cleanupModel,
            writingStyle: writingStyle,
            language: language,
            useSpellCheckHints: useSpellCheckHints
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
        writingStyle: WritingStyle = .casual,
        useSpellCheckHints: Bool = true,
        mutesSystemAudioWhileDictating: Bool = true
    ) {
        self.language = language
        self.keepWarmSeconds = keepWarmSeconds
        self.trigger = trigger
        self.asrBackend = asrBackend
        self.asrModel = asrModel
        self.openRouterModel = openRouterModel
        self.writingStyle = writingStyle
        self.useSpellCheckHints = useSpellCheckHints
        self.mutesSystemAudioWhileDictating = mutesSystemAudioWhileDictating
    }
}
