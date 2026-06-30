import Foundation

/// Narrow read seam for `UserDefaults`, so malformed persisted config can be
/// tested without touching the process-wide defaults database.
public protocol UserDefaultsReading {
    func data(forKey defaultName: String) -> Data?
}

extension UserDefaults: UserDefaultsReading {}

public enum ConfigStore {
    public static let defaultKey = "loqui.config.v1"

    public static func load(from defaults: UserDefaultsReading, key: String = defaultKey) -> Config {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(StoredConfig.self, from: data),
              let config = decoded.validated()
        else {
            return .defaults
        }
        return config
    }

    private struct StoredConfig: Decodable {
        let language: Language
        let keepWarmSeconds: Int
        let trigger: String?
        let mode: String?
        let asr: StoredAsr
        let cleanup: StoredCleanup

        func validated() -> Config? {
            guard (0...3_600).contains(keepWarmSeconds),
                  trigger == nil || trigger == Config.defaultTrigger,
                  mode == nil || mode == Config.defaultMode,
                  asr.backend == .whisperKit,
                  !asr.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !cleanup.anthropicModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }

            return Config(
                language: language,
                keepWarmSeconds: keepWarmSeconds,
                asrBackend: asr.backend,
                asrModel: asr.model,
                cleanupEnabled: cleanup.enabled,
                anthropicModel: cleanup.anthropicModel,
                writingStyle: cleanup.writingStyle
            )
        }
    }

    private struct StoredAsr: Decodable {
        let backend: AsrBackend
        let model: String
    }

    private struct StoredCleanup: Decodable {
        let enabled: Bool
        let anthropicModel: String
        let writingStyle: WritingStyle
    }
}
