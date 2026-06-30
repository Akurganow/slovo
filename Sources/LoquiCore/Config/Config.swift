import Foundation

/// User-editable app configuration persisted as the spec §10 JSON shape.
public struct Config: Equatable, Sendable {
    public static let defaultTrigger = "fn"
    public static let defaultMode = "hold"

    public static let defaults = Config()

    public var language: Language
    public var keepWarmSeconds: Int
    public var asrBackend: AsrBackend
    public var asrModel: String
    public var cleanupEnabled: Bool
    public var anthropicModel: String
    public var writingStyle: WritingStyle

    public var cleanupConfig: CleanupConfig {
        CleanupConfig(model: anthropicModel, writingStyle: writingStyle, language: language)
    }

    public init(
        language: Language = .auto,
        keepWarmSeconds: Int = 120,
        asrBackend: AsrBackend = .whisperKit,
        asrModel: String = "large-v3-v20240930_turbo_632MB",
        cleanupEnabled: Bool = true,
        anthropicModel: String = "claude-haiku-4-5",
        writingStyle: WritingStyle = .casual
    ) {
        self.language = language
        self.keepWarmSeconds = keepWarmSeconds
        self.asrBackend = asrBackend
        self.asrModel = asrModel
        self.cleanupEnabled = cleanupEnabled
        self.anthropicModel = anthropicModel
        self.writingStyle = writingStyle
    }
}
