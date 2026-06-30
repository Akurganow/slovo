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

    /// Stated sensitivity: accept an empty Anthropic model string → the invalid
    /// config survives and this defaults assertion fails.
    @Test
    func emptyAnthropicModelRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(anthropicModel: ""),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// Stated sensitivity: validate inactive provider models globally -> a valid
    /// Anthropic config is thrown away because an unused OpenAI model is empty.
    @Test
    func emptyInactiveOpenAIModelDoesNotRejectAnthropicConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(
                cleanupProvider: "anthropic",
                anthropicModel: "claude-active",
                openAIModel: ""
            ),
        ])

        let config = ConfigStore.load(from: defaults)

        #expect(config.cleanupProvider == .anthropic)
        #expect(config.cleanupConfig.model == "claude-active")
    }

    /// Stated sensitivity: ignore `cleanup.provider` or keep selecting Anthropic
    /// while the stored config asks for OpenAI -> loaded cleanupBackend is wrong.
    @Test
    func openAIProviderAndModelDecodeFromCleanupConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(
                cleanupProvider: "openai",
                anthropicModel: "claude-experiment",
                openAIModel: "gpt-5.4-mini",
                writingStyle: "casual"
            ),
        ])

        let config = ConfigStore.load(from: defaults)

        #expect(config.cleanupProvider == .openAI)
        #expect(config.anthropicModel == "claude-experiment")
        #expect(config.openAIModel == "gpt-5.4-mini")
        #expect(config.cleanupConfig.model == "gpt-5.4-mini",
                "the active cleanup model must follow the selected provider")
    }

    /// Stated sensitivity: require the new provider/model fields unconditionally
    /// -> old persisted configs fall back to defaults and lose valid user config.
    @Test
    func legacyCleanupConfigWithoutProviderStaysAnthropicCompatible() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(anthropicModel: "claude-legacy-model"),
        ])

        let config = ConfigStore.load(from: defaults)

        #expect(config.cleanupProvider == .anthropic)
        #expect(config.anthropicModel == "claude-legacy-model")
        #expect(config.openAIModel == Config.defaults.openAIModel)
        #expect(config.cleanupConfig.model == "claude-legacy-model")
    }

    /// Stated sensitivity: accept an unknown cleanup provider -> the app silently
    /// runs a different cloud egress path than the persisted config names.
    @Test
    func unknownCleanupProviderRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(cleanupProvider: "local-llm"),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// Stated sensitivity: accept an empty OpenAI model while provider=openai ->
    /// the live request would reach the API with an invalid model id.
    @Test
    func emptyOpenAIModelRejectsOpenAIConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try Self.configData(cleanupProvider: "openai", openAIModel: ""),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// Stated sensitivity: omit `cleanup.provider` or `cleanup.openAIModel`
    /// while saving -> load round-trip falls back to Anthropic/defaults.
    @Test
    func saveRoundTripsCleanupProviderAndProviderModels() throws {
        let defaults = FakeUserDefaults()
        let config = Config(
            cleanupProvider: .openAI,
            anthropicModel: "claude-saved",
            openAIModel: "gpt-saved"
        )

        try ConfigStore.save(config, to: defaults)
        let loaded = ConfigStore.load(from: defaults)

        #expect(loaded.cleanupProvider == .openAI)
        #expect(loaded.anthropicModel == "claude-saved")
        #expect(loaded.openAIModel == "gpt-saved")
        #expect(loaded.cleanupConfig.model == "gpt-saved")
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
                cleanupProvider: "openai",
                anthropicModel: "claude-haiku-4-5",
                openAIModel: "gpt-5.4-mini",
                writingStyle: "formal"
            ),
        ])

        #expect(ConfigStore.load(from: defaults) == Config(
            language: .ru,
            keepWarmSeconds: 45,
            asrBackend: .whisperKit,
            asrModel: "large-v3-v20240930_turbo_632MB",
            cleanupEnabled: false,
            cleanupProvider: .openAI,
            anthropicModel: "claude-haiku-4-5",
            openAIModel: "gpt-5.4-mini",
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
        anthropicModel: String = "claude-haiku-4-5",
        openAIModel: String? = nil,
        writingStyle: String = "casual"
    ) throws -> Data {
        var cleanup: [String: Any] = [
            "enabled": cleanupEnabled,
            "anthropicModel": anthropicModel,
            "writingStyle": writingStyle,
        ]
        if let cleanupProvider {
            cleanup["provider"] = cleanupProvider
        }
        if let openAIModel {
            cleanup["openAIModel"] = openAIModel
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
