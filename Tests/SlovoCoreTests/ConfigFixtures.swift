import Foundation

/// Builds spec §10 persisted-config JSON blobs for `ConfigStore` decode tests.
/// A field passed as `nil` (where optional) is OMITTED from the wire blob, so
/// callers can exercise absent-field decode paths.
enum ConfigFixtures {
    static func configData(
        trigger: String? = "fn",
        mode: String? = "hold",
        language: String = "ru",
        keepWarmSeconds: Int? = 45,
        backend: String = "whisperkit",
        asrModel: String = "large-v3-v20240930_turbo_632MB",
        legacyEnabledField: Bool = true,
        cleanupProvider: String? = nil,
        openRouterModel: String? = nil,
        writingStyle: String = "casual"
    ) throws -> Data {
        var cleanup: [String: Any] = [
            "enabled": legacyEnabledField,
            "writingStyle": writingStyle,
        ]
        if let cleanupProvider {
            cleanup["provider"] = cleanupProvider
        }
        if let openRouterModel {
            cleanup["openRouterModel"] = openRouterModel
        }
        var object: [String: Any] = [
            "language": language,
            "asr": ["backend": backend, "model": asrModel],
            "cleanup": cleanup,
        ]
        if let keepWarmSeconds {
            object["keepWarmSeconds"] = keepWarmSeconds
        }
        if let trigger {
            object["trigger"] = trigger
        }
        if let mode {
            object["mode"] = mode
        }
        return try encoded(object)
    }

    static func encoded(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
