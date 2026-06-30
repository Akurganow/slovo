import Foundation

/// Narrow read seam for `UserDefaults`, so malformed persisted config can be
/// tested without touching the process-wide defaults database.
public protocol UserDefaultsReading {
    func data(forKey defaultName: String) -> Data?
}

extension UserDefaults: UserDefaultsReading {}

public protocol UserDefaultsWriting: UserDefaultsReading {
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: UserDefaultsWriting {}

public enum ConfigStore {
    public static let defaultKey = "loqui.config.v1"

    public enum SaveError: Error, Sendable {
        case invalidConfig
    }

    public static func load(from defaults: UserDefaultsReading, key: String = defaultKey) -> Config {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(StoredConfig.self, from: data),
              let config = decoded.validated()
        else {
            return .defaults
        }
        return config
    }

    public static func save(_ config: Config, to defaults: UserDefaultsWriting, key: String = defaultKey) throws {
        guard validated(config) != nil else {
            throw SaveError.invalidConfig
        }
        let stored = StoredConfig(config: config)
        let data = try JSONEncoder().encode(stored)
        defaults.set(data, forKey: key)
    }

    private struct StoredConfig: Codable {
        let language: Language
        let keepWarmSeconds: Int
        let trigger: String?
        let mode: String?
        let asr: StoredAsr
        let cleanup: StoredCleanup

        func validated() -> Config? {
            guard trigger == nil || trigger == Config.defaultTrigger,
                  mode == nil || mode == Config.defaultMode
            else {
                return nil
            }

            let provider = cleanup.provider ?? .anthropic
            let openAIModel = cleanup.openAIModel ?? Config.defaultOpenAIModel

            return ConfigStore.validated(Config(
                language: language,
                keepWarmSeconds: keepWarmSeconds,
                asrBackend: asr.backend,
                asrModel: asr.model,
                cleanupEnabled: cleanup.enabled,
                cleanupProvider: provider,
                anthropicModel: cleanup.anthropicModel,
                openAIModel: openAIModel,
                writingStyle: cleanup.writingStyle
            ))
        }

        init(config: Config) {
            language = config.language
            keepWarmSeconds = config.keepWarmSeconds
            trigger = Config.defaultTrigger
            mode = Config.defaultMode
            asr = StoredAsr(backend: config.asrBackend, model: config.asrModel)
            cleanup = StoredCleanup(
                enabled: config.cleanupEnabled,
                provider: config.cleanupProvider,
                anthropicModel: config.anthropicModel,
                openAIModel: config.openAIModel,
                writingStyle: config.writingStyle
            )
        }
    }

    private struct StoredAsr: Codable {
        let backend: AsrBackend
        let model: String
    }

    private struct StoredCleanup: Codable {
        let enabled: Bool
        let provider: CleanupProvider?
        let anthropicModel: String
        let openAIModel: String?
        let writingStyle: WritingStyle
    }

    private static func validated(_ config: Config) -> Config? {
        guard (0...3_600).contains(config.keepWarmSeconds),
              config.asrBackend == .whisperKit,
              !config.asrModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              hasModel(for: config.cleanupProvider, in: config)
        else {
            return nil
        }
        return config
    }

    private static func hasModel(for provider: CleanupProvider, in config: Config) -> Bool {
        switch provider {
        case .anthropic:
            return !config.anthropicModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .openAI:
            return !config.openAIModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
