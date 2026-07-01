/// User-editable app configuration persisted as the spec §10 JSON shape.
public struct Config: Equatable, Sendable {
    public static let defaultTrigger = "fn"
    public static let defaultMode = "hold"
    public static let defaultOpenRouterModel = CleanupDefaults.openRouterModel

    public static let defaults = Config()

    public var language: Language
    public var keepWarmSeconds: Int
    public var asrBackend: AsrBackend
    public var asrModel: String
    public var cleanupEnabled: Bool
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
        keepWarmSeconds: Int = 120,
        asrBackend: AsrBackend = .whisperKit,
        asrModel: String = "large-v3-v20240930_turbo_632MB",
        cleanupEnabled: Bool = true,
        openRouterModel: String = Config.defaultOpenRouterModel,
        writingStyle: WritingStyle = .casual
    ) {
        self.language = language
        self.keepWarmSeconds = keepWarmSeconds
        self.asrBackend = asrBackend
        self.asrModel = asrModel
        self.cleanupEnabled = cleanupEnabled
        self.openRouterModel = openRouterModel
        self.writingStyle = writingStyle
    }
}
