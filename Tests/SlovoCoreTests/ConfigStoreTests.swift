import Foundation
import Testing

@testable import SlovoCore
import SlovoTestSupport

// A blob that cannot be read as a whole (no data, malformed JSON) falls back to
// defaults without crashing or leaking partially decoded garbage into the app. A
// single unreadable field, an out-of-range keep-warm included, is recovered per
// field in ConfigStoreRecoveryTests.
@Suite("ConfigStore")
struct ConfigStoreTests {
    @Test
    func missingConfigReturnsDefaults() {
        let defaults = FakeUserDefaults()

        #expect(ConfigStore.load(from: defaults) == .defaults)
        #expect(Config.defaults.asrBackend == .whisperKit)
        #expect(Config.defaults.asrModel == "large-v3-v20240930_turbo_632MB")
        #expect(Config.defaults.cleanupModel == Config.defaultOpenRouterModel)
        // Resident by default: nil keepWarm means the model is never released.
        #expect(Config.defaults.keepWarmSeconds == nil)
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

    /// The keep-warm setting is load-bearing for WhisperKit model retention: a
    /// positive value keeps the loaded engine warm for that many idle seconds
    /// before release, while zero releases immediately after each use.
    /// Stated sensitivity: dropping the decoded value or silently defaulting it
    /// means this no longer round-trips.
    @Test
    func keepWarmSecondsIsLoadedForWhisperKitRetention() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(keepWarmSeconds: 45),
        ])

        #expect(ConfigStore.load(from: defaults).keepWarmSeconds == 45)
    }

    /// The save side refuses a keep-warm window outside 0...3600 and accepts both
    /// ends. Load keeps such a value out of the config field by field, so only `save`
    /// and `isValid` enforce this range.
    /// Stated sensitivity: delete the keep-warm range check from `validated` → the
    /// out-of-range saves succeed and `isValid` is true → RED.
    @Test
    func saveAndIsValidRefuseKeepWarmOutsideTheRange() throws {
        for seconds in [-1, 3_601] {
            let config = Config(keepWarmSeconds: seconds)

            #expect(throws: ConfigStore.SaveError.self) {
                try ConfigStore.save(config, to: FakeUserDefaults())
            }
            #expect(!ConfigStore.isValid(config))
        }
        for seconds in [0, 3_600] {
            let config = Config(keepWarmSeconds: seconds)

            #expect(ConfigStore.isValid(config))
            try ConfigStore.save(config, to: FakeUserDefaults())
        }
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

    @Test
    func validConfigDecodesSpecShape() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(
                language: "ru",
                keepWarmSeconds: 45,
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
            keepWarmSeconds: 45,
            asrBackend: .whisperKit,
            asrModel: "large-v3-v20240930_turbo_632MB",
            openRouterModel: "openai/gpt-6-luna",
            cleanupEnabled: false,
            writingStyle: .formal
        ))
    }

    /// Persisted configs from the abandoned Apple-Speech migration used backend
    /// "speechtranscriber" + model "system-dictation". Those legacy values MIGRATE
    /// to the WhisperKit turbo runtime on load (a mapping, not a recovery): the
    /// single-case `AsrBackend`'s synthesized Codable cannot even represent
    /// "speechtranscriber", so the loader maps the legacy string BEFORE raw-value
    /// matching. keepWarmSeconds RESETS to resident (nil) for any
    /// legacy value (legacy keepWarm meant Apple retention, not an idle window).
    /// Unrelated cleanup/style fields survive untouched.
    ///
    /// Anti-tautology: after migration asrBackend/asrModel/keepWarmSeconds ALL equal
    /// their new defaults (.whisperKit / turbo / nil), so asserting any of those
    /// alone is false-green — the BROKEN discard-to-defaults path satisfies them too.
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
                keepWarmSeconds: 999,
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
        // The migration mapping itself (each equals a NEW default, hence tautological alone).
        #expect(config.asrBackend == .whisperKit)
        #expect(config.asrModel == "large-v3-v20240930_turbo_632MB")
        #expect(config.keepWarmSeconds == nil)
    }

    /// `ConfigStore.validated` accepts a WhisperKit config with a non-empty model,
    /// so such a config survives a save→load cycle unchanged.
    /// Stated sensitivity: reject `.whisperKit` at validation, or drop the model on
    /// save/load, → the reloaded config differs from the saved one → RED.
    @Test
    func whisperKitConfigRoundTripsThroughSaveAndLoad() throws {
        let defaults = FakeUserDefaults()
        let config = Config(
            keepWarmSeconds: 90,
            asrBackend: .whisperKit,
            asrModel: "large-v3-v20240930_turbo_632MB",
            openRouterModel: "openai/gpt-6-luna"
        )

        try ConfigStore.save(config, to: defaults)

        #expect(ConfigStore.load(from: defaults) == config)
    }

    /// Wire compat: a persisted blob with NO keepWarm field decodes to the resident
    /// default (nil), not a numeric fallback or a whole-config rejection.
    /// Stated sensitivity: decode an absent keepWarm field as 0/120 (or reject the
    /// config) → keepWarmSeconds is not nil → RED.
    @Test
    func absentKeepWarmDecodesAsResident() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(keepWarmSeconds: nil),
        ])

        #expect(ConfigStore.load(from: defaults).keepWarmSeconds == nil)
    }

    /// Legacy keepWarm resets to resident (nil) REGARDLESS of value — the 120 case,
    /// companion to the 999 case in `legacyAppleSpeechConfigMigratesToWhisperKit`.
    /// Testing both values proves the reset is not value-specific (120, the old
    /// Apple-Speech default, is not special).
    /// Stated sensitivity: carry a legacy keepWarm verbatim (no reset) → 120 survives
    /// as 120 instead of nil → RED.
    @Test
    func legacyKeepWarm120ResetsToResident() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(
                keepWarmSeconds: 120,
                backend: "speechtranscriber",
                asrModel: "system-dictation"
            ),
        ])

        let config = ConfigStore.load(from: defaults)

        #expect(config.keepWarmSeconds == nil, "legacy keepWarm resets to resident (nil) for any value")
        #expect(config.asrBackend == .whisperKit)
        #expect(config.asrModel == "large-v3-v20240930_turbo_632MB")
    }

    /// The keepWarm reset is LEGACY-ONLY: a current WhisperKit blob PRESERVES its
    /// explicit keepWarm window (the user's choice) — only "speechtranscriber" blobs
    /// reset to resident.
    /// Stated sensitivity: reset non-legacy keepWarm too → a WhisperKit user's
    /// explicit 30 s window is silently lost to nil → RED.
    @Test
    func whisperKitKeepWarmIsPreserved() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(keepWarmSeconds: 30, backend: "whisperkit"),
        ])

        #expect(ConfigStore.load(from: defaults).keepWarmSeconds == 30)
    }
}
