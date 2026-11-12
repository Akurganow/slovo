import Foundation
import Testing

@testable import SlovoCore
import SlovoTestSupport

// A blob that cannot be read as a whole (no data, malformed JSON) falls back to
// defaults without crashing or leaking partially decoded garbage into the app. A
// single unreadable field is recovered per field in ConfigStoreRecoveryTests.
@Suite("ConfigStore")
struct ConfigStoreTests {
    @Test
    func missingConfigReturnsDefaults() {
        let defaults = FakeUserDefaults()

        #expect(ConfigStore.load(from: defaults) == .defaults)
        #expect(Config.defaults.asrModel == "large-v3-v20240930_turbo_632MB")
        #expect(Config.defaults.cleanupModel == Config.defaultOpenRouterModel)
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

    /// A blank or whitespace-only model id is refused on save for either engine, and
    /// `isValid` agrees. Load replaces such an id with the default instead.
    /// Stated sensitivity: let `validated` accept a blank `asrModel` → the save
    /// succeeds → RED. The same for a blank `openRouterModel` → RED.
    @Test
    func saveAndIsValidRefuseBlankModelIds() {
        for blank in ["", "  "] {
            let asrConfig = Config(asrModel: blank)
            let openRouterConfig = Config(openRouterModel: blank)

            #expect(throws: ConfigStore.SaveError.self) {
                try ConfigStore.save(asrConfig, to: FakeUserDefaults())
            }
            #expect(!ConfigStore.isValid(asrConfig))
            #expect(throws: ConfigStore.SaveError.self) {
                try ConfigStore.save(openRouterConfig, to: FakeUserDefaults())
            }
            #expect(!ConfigStore.isValid(openRouterConfig))
        }
    }

    /// Stated sensitivity: treat OpenRouter as an ad hoc string or forget its
    /// model field -> stored routed-cloud cleanup selection is rejected or falls
    /// back to a different provider.
    @Test
    func openRouterProviderAndModelDecodeFromCleanupConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(
                cleanupProvider: "openrouter",
                openRouterModel: "openai/gpt-6-luna"
            ),
        ])

        let config = ConfigStore.load(from: defaults)

        #expect(config.openRouterModel == "openai/gpt-6-luna")
        #expect(config.cleanupConfig.model == "openai/gpt-6-luna")
    }

    /// Stated sensitivity: require the provider field unconditionally -> a
    /// minimal persisted config falls back to defaults and loses valid settings.
    @Test
    func cleanupConfigWithoutProviderStaysOpenRouterCompatible() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(
                legacyEnabledField: false,
                openRouterModel: "openai/gpt-6-luna"
            ),
        ])

        let config = ConfigStore.load(from: defaults)

        #expect(config.openRouterModel == "openai/gpt-6-luna")
        #expect(config.cleanupConfig.model == "openai/gpt-6-luna")
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
        #expect(cleanup["enabled"] as? Bool == true)
    }

    /// An older build requires `asr.backend` in the stored blob, so a save must carry it.
    /// Stated sensitivity: drop `StoredAsr.backend`, or change its value → RED.
    @Test
    func savedConfigWritesTheWhisperKitBackendKey() throws {
        let defaults = FakeUserDefaults()

        try ConfigStore.save(.defaults, to: defaults)

        let raw = try #require(defaults.data(forKey: ConfigStore.defaultKey))
        let object = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        #expect((object["asr"] as? [String: Any])?["backend"] as? String == "whisperkit")
    }

    @Test
    func validConfigDecodesSpecShape() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(
                language: "ru",
                backend: "whisperkit",
                asrModel: "large-v3-v20240930_turbo_632MB",
                legacyEnabledField: false,
                cleanupProvider: "openrouter",
                openRouterModel: "openai/gpt-6-luna",
                writingStyle: "formal"
            ),
        ])

        #expect(ConfigStore.load(from: defaults) == Config(
            language: .ru,
            asrModel: "large-v3-v20240930_turbo_632MB",
            openRouterModel: "openai/gpt-6-luna",
            cleanupEnabled: false,
            writingStyle: .formal
        ))
    }

    /// Persisted configs from the abandoned Apple-Speech migration used backend
    /// "speechtranscriber" + model "system-dictation". Those legacy values MIGRATE
    /// to the WhisperKit turbo runtime on load (a mapping, not a recovery).
    /// Unrelated cleanup/style fields survive untouched.
    ///
    /// Anti-tautology: after migration asrModel equals its new default (turbo), so
    /// asserting it alone is false-green — the BROKEN discard-to-defaults path
    /// satisfies it too.
    /// The load-bearing assertion is a NON-DEFAULT surviving sibling: `writingStyle:
    /// .formal` (≠ .casual default) and a non-default openRouterModel the user set.
    /// Stated sensitivity: reset the whole config on the legacy backend → the
    /// non-default writingStyle/openRouterModel are lost → RED. Skip the model remap
    /// → asrModel stays "legacy-other-model" → RED. The stored model is not
    /// "system-dictation", so only the backend can trigger the remap. Report the
    /// legacy backend as recovered → the recovered set is not empty → RED.
    @Test
    func legacyAppleSpeechConfigMigratesToWhisperKit() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(
                backend: "speechtranscriber",
                asrModel: "legacy-other-model",
                cleanupProvider: "openrouter",
                openRouterModel: "openai/gpt-6-nano",
                writingStyle: "formal"
            ),
        ])

        let loaded = ConfigStore.loadRecovering(from: defaults)
        let config = loaded.config

        #expect(loaded.recoveredKeys.isEmpty, "the migration is not damage, so it reports nothing")
        // Load-bearing anti-tautology siblings: NON-DEFAULT fields the user set, which
        // a whole-config fallback to defaults would destroy.
        #expect(config.writingStyle == .formal)
        #expect(config.openRouterModel == "openai/gpt-6-nano")
        #expect(config != .defaults)
        // The migration mapping itself (it equals a NEW default, hence tautological alone).
        #expect(config.asrModel == "large-v3-v20240930_turbo_632MB")
    }

    /// `ConfigStore.validated` accepts a config with a non-empty model, so such a
    /// config survives a save→load cycle unchanged.
    /// Stated sensitivity: reject the config at validation, or drop the model on
    /// save/load, → the reloaded config differs from the saved one → RED.
    @Test
    func whisperKitConfigRoundTripsThroughSaveAndLoad() throws {
        let defaults = FakeUserDefaults()
        let config = Config(
            asrModel: "large-v3-v20240930_turbo_632MB",
            openRouterModel: "openai/gpt-6-luna"
        )

        try ConfigStore.save(config, to: defaults)

        #expect(ConfigStore.load(from: defaults) == config)
    }
}
