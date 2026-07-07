/// User-editable app configuration persisted as JSON.
public struct Config: Equatable, Sendable {
    public static let defaultTrigger = "fn"
    public static let defaultMode = "hold"
    public static let defaultAsrModel = "large-v3-v20240930_turbo_632MB"
    public static let defaultOpenRouterModel = CleanupDefaults.openRouterModel

    public static let defaults = Config()

    public var language: Language
    /// WhisperKit model retention: `nil` keeps the model resident by default
    /// (fastest first word), `0` releases immediately after each dictation, a
    /// positive value is the idle-seconds window before release.
    public var keepWarmSeconds: Int?
    public var asrBackend: AsrBackend
    public var asrModel: String
    public var openRouterModel: String
    public var writingStyle: WritingStyle

    public var cleanupConfig: CleanupConfig {
        CleanupConfig(model: cleanupModel, writingStyle: writingStyle, language: language)
    }

    public var cleanupModel: String {
        openRouterModel
    }

    public init(
        language: Language = .auto,
        keepWarmSeconds: Int? = nil,
        asrBackend: AsrBackend = .whisperKit,
        asrModel: String = Config.defaultAsrModel,
        openRouterModel: String = Config.defaultOpenRouterModel,
        writingStyle: WritingStyle = .casual
    ) {
        self.language = language
        self.keepWarmSeconds = keepWarmSeconds
        self.asrBackend = asrBackend
        self.asrModel = asrModel
        self.openRouterModel = openRouterModel
        self.writingStyle = writingStyle
    }
}
