import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Epic 09b — AC-3: config decode is fail-closed. Malformed JSON, unknown enum
// values, and invalid numeric/string fields must fall back to defaults without
// crashing or leaking partially decoded garbage into the app.
@Suite("Epic 09b AC-3 ConfigStore")
struct ConfigStoreTests {
    @Test
    func missingConfigReturnsDefaults() {
        let defaults = FakeUserDefaults()

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// Stated sensitivity: force-unwrap/decode directly or keep partially decoded
    /// garbage → this either crashes or returns something other than defaults.
    @Test
    func malformedJsonReturnsDefaultsWithoutCrashing() {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: Data("{not-json".utf8),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// Stated sensitivity: accept an unknown ASR backend instead of rejecting the
    /// whole config → the loaded config is not `.defaults` and this goes RED.
    @Test
    func unknownBackendRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(backend: "experimentalBackend"),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// Stated sensitivity: accepting a documented-but-unwired backend makes the
    /// production composition silently run WhisperKit for a non-WhisperKit config.
    @Test
    func unsupportedRuntimeBackendRejectsWholeConfig() throws {
        for backend in ["speechtranscriber", "fluidaudio"] {
            let defaults = FakeUserDefaults(dataByKey: [
                ConfigStore.defaultKey: try Self.configData(backend: backend),
            ])

            #expect(ConfigStore.load(from: defaults) == .defaults,
                    "backend \(backend) must stay fail-closed until a production adapter is wired")
        }
    }

    /// The keep-warm setting is load-bearing for the live WhisperKit adapter.
    /// Stated sensitivity: dropping the decoded value or silently defaulting it
    /// means this no longer round-trips.
    @Test
    func keepWarmSecondsIsLoadedForLiveModelLifecycle() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(keepWarmSeconds: 45),
        ])

        #expect(ConfigStore.load(from: defaults).keepWarmSeconds == 45)
    }

    /// Stated sensitivity: accept a negative keep-warm duration → the invalid
    /// config survives and this defaults assertion fails.
    @Test
    func negativeKeepWarmRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(keepWarmSeconds: -1),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// Stated sensitivity: accept an empty ASR model string → the invalid config
    /// survives and this defaults assertion fails.
    @Test
    func emptyAsrModelRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(asrModel: ""),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// Stated sensitivity: accept an empty OpenRouter model string -> the live
    /// request would reach OpenRouter with an invalid model id.
    @Test
    func emptyOpenRouterModelRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(openRouterModel: ""),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// Stated sensitivity: accepting a forbidden direct provider as active, or
    /// falling back to cleanup-enabled defaults, can silently egress transcripts.
    @Test
    func forbiddenAnthropicProviderDisablesCleanupWithoutResettingSettings() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(
                cleanupEnabled: true,
                cleanupProvider: "anthropic",
                writingStyle: "formal"
            ),
        ])

        let config = ConfigStore.load(from: defaults)

        #expect(config.language == .ru)
        #expect(config.keepWarmSeconds == 45)
        #expect(config.cleanupEnabled == false)
        #expect(config.openRouterModel == Config.defaultOpenRouterModel)
        #expect(config.writingStyle == .formal)
    }

    /// Stated sensitivity: keep treating a forbidden OpenAI provider as active
    /// instead of forcing local pass-through behavior.
    @Test
    func forbiddenOpenAIProviderDisablesCleanup() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(cleanupProvider: "openai"),
        ])

        let config = ConfigStore.load(from: defaults)

        #expect(config.cleanupEnabled == false)
        #expect(config.openRouterModel == Config.defaultOpenRouterModel)
        #expect(config.cleanupConfig.model == Config.defaultOpenRouterModel)
    }

    /// Stated sensitivity: treat OpenRouter as an ad hoc string or forget its
    /// model field -> stored routed-cloud cleanup selection is rejected or falls
    /// back to a different provider.
    @Test
    func openRouterProviderAndModelDecodeFromCleanupConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(
                cleanupProvider: "openrouter",
                openRouterModel: "openai/gpt-5.4-nano"
            ),
        ])

        let config = ConfigStore.load(from: defaults)

        #expect(config.openRouterModel == "openai/gpt-5.4-nano")
        #expect(config.cleanupConfig.model == "openai/gpt-5.4-nano")
    }

    /// Stated sensitivity: require the provider field unconditionally -> a
    /// minimal persisted config falls back to defaults and loses valid settings.
    @Test
    func cleanupConfigWithoutProviderStaysOpenRouterCompatible() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(openRouterModel: "openai/gpt-5.4-nano"),
        ])

        let config = ConfigStore.load(from: defaults)

        #expect(config.openRouterModel == "openai/gpt-5.4-nano")
        #expect(config.cleanupConfig.model == "openai/gpt-5.4-nano")
    }

    /// Stated sensitivity: accept an unknown cleanup provider as active -> the
    /// app silently runs a different cloud egress path than persisted config.
    @Test
    func unknownCleanupProviderDisablesCleanup() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(cleanupProvider: "local-llm"),
        ])

        #expect(ConfigStore.load(from: defaults).cleanupEnabled == false)
    }

    /// Stated sensitivity: omit `cleanup.openRouterModel` while saving -> load
    /// round-trip falls back to defaults.
    @Test
    func saveRoundTripsOpenRouterModelWithoutProviderField() throws {
        let defaults = FakeUserDefaults()
        let config = Config(
            openRouterModel: "openrouter-saved"
        )

        try ConfigStore.save(config, to: defaults)
        let loaded = ConfigStore.load(from: defaults)

        #expect(loaded.openRouterModel == "openrouter-saved")
        #expect(loaded.cleanupConfig.model == "openrouter-saved")

        let raw = try #require(defaults.data(forKey: ConfigStore.defaultKey))
        let object = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let cleanup = try #require(object["cleanup"] as? [String: Any])
        #expect(cleanup["provider"] == nil)
    }

    /// Stated sensitivity: decoding persisted ASR backend from the Swift case
    /// name instead of the documented wire format must be rejected independently.
    @Test
    func swiftCaseBackendRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(backend: "whisperKit"),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// Stated sensitivity: decoding persisted writing style from the Swift case
    /// name instead of the documented wire format must be rejected independently.
    @Test
    func swiftCaseWritingStyleRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(writingStyle: "veryCasual"),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// Stated sensitivity: ignoring fixed v1 trigger accepts a value the app
    /// cannot execute.
    @Test
    func invalidFixedTriggerRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(trigger: "capslock"),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// Stated sensitivity: ignoring fixed v1 mode accepts a value the app cannot
    /// execute.
    @Test
    func invalidFixedModeRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(mode: "toggle"),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    @Test
    func validConfigDecodesSpecShape() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(
                language: "ru",
                keepWarmSeconds: 45,
                backend: "whisperkit",
                asrModel: "large-v3-v20240930_turbo_632MB",
                cleanupEnabled: false,
                cleanupProvider: "openrouter",
                openRouterModel: "openai/gpt-5.4-nano",
                writingStyle: "formal"
            ),
        ])

        #expect(ConfigStore.load(from: defaults) == Config(
            language: .ru,
            keepWarmSeconds: 45,
            asrBackend: .whisperKit,
            asrModel: "large-v3-v20240930_turbo_632MB",
            cleanupEnabled: false,
            openRouterModel: "openai/gpt-5.4-nano",
            writingStyle: .formal
        ))
    }

    private static func configData(
        trigger: String? = "fn",
        mode: String? = "hold",
        language: String = "ru",
        keepWarmSeconds: Int = 45,
        backend: String = "whisperkit",
        asrModel: String = "large-v3-v20240930_turbo_632MB",
        cleanupEnabled: Bool = true,
        cleanupProvider: String? = nil,
        openRouterModel: String? = nil,
        writingStyle: String = "casual"
    ) throws -> Data {
        var cleanup: [String: Any] = [
            "enabled": cleanupEnabled,
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
            "keepWarmSeconds": keepWarmSeconds,
            "asr": ["backend": backend, "model": asrModel],
            "cleanup": cleanup,
        ]
        if let trigger {
            object["trigger"] = trigger
        }
        if let mode {
            object["mode"] = mode
        }
        return try encoded(object)
    }

    private static func encoded(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
