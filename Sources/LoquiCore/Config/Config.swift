import Foundation

/// User-editable app configuration persisted as the spec §10 JSON shape.
public struct Config: Equatable, Sendable {
    public static let defaultTrigger = "fn"
    public static let defaultMode = "hold"
    public static let defaultAnthropicModel = "claude-haiku-4-5"
    public static let defaultOpenAIModel = "gpt-5.4-mini"

    public static let defaults = Config()

    public var language: Language
    public var keepWarmSeconds: Int
    public var asrBackend: AsrBackend
    public var asrModel: String
    public var cleanupEnabled: Bool
    public var cleanupProvider: CleanupProvider
    public var anthropicModel: String
    public var openAIModel: String
    public var writingStyle: WritingStyle

    public var cleanupConfig: CleanupConfig {
        CleanupConfig(model: cleanupModel, writingStyle: writingStyle, language: language)
    }

    public var cleanupModel: String {
        switch cleanupProvider {
        case .anthropic:
            return anthropicModel
        case .openAI:
            return openAIModel
        }
    }

    public init(
        language: Language = .auto,
        keepWarmSeconds: Int = 120,
        asrBackend: AsrBackend = .whisperKit,
        asrModel: String = "large-v3-v20240930_turbo_632MB",
        cleanupEnabled: Bool = true,
        cleanupProvider: CleanupProvider = .anthropic,
        anthropicModel: String = Config.defaultAnthropicModel,
        openAIModel: String = Config.defaultOpenAIModel,
        writingStyle: WritingStyle = .casual
    ) {
        self.language = language
        self.keepWarmSeconds = keepWarmSeconds
        self.asrBackend = asrBackend
        self.asrModel = asrModel
        self.cleanupEnabled = cleanupEnabled
        self.cleanupProvider = cleanupProvider
        self.anthropicModel = anthropicModel
        self.openAIModel = openAIModel
        self.writingStyle = writingStyle
    }
}
