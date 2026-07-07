import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Config decode is fail-closed. Malformed JSON, unknown enum
// values, and invalid numeric/string fields must fall back to defaults without
// crashing or leaking partially decoded garbage into the app.
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

    /// Stated sensitivity: accept an unknown ASR backend instead of rejecting the
    /// whole config → the loaded config is not `.defaults` and this goes RED.
    @Test
    func unknownBackendRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(backend: "experimentalBackend"),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// A refuted backend id (FluidAudio: no shipped adapter) must fail closed, not
    /// be silently rerouted to WhisperKit. This is distinct from the legacy
    /// Apple-Speech id, which is intentionally migrated (see
    /// `legacyAppleSpeechConfigMigratesToWhisperKit`): the migration is SPECIFIC,
    /// not a catch-all that swallows any unrecognized backend into the runtime.
    /// Stated sensitivity: make backend decoding map every unrecognized id to
    /// `.whisperKit` → "fluidaudio" loads as a whisperKit config (keepWarm 45)
    /// instead of falling back to defaults → RED.
    @Test
    func refutedRuntimeBackendRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(backend: "fluidaudio"),
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

    /// Stated sensitivity: accept a negative keep-warm duration → the invalid
    /// config survives and this defaults assertion fails.
    @Test
    func negativeKeepWarmRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(keepWarmSeconds: -1),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// Stated sensitivity: accept an empty ASR model string → the invalid config
    /// survives and this defaults assertion fails.
    @Test
    func emptyAsrModelRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(asrModel: ""),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// Stated sensitivity: accept an empty OpenRouter model string -> the live
    /// request would reach OpenRouter with an invalid model id.
    @Test
    func emptyOpenRouterModelRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(openRouterModel: ""),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// Stated sensitivity: preserving a forbidden direct provider or converting
    /// it into a user-off state lets legacy provider config keep controlling
    /// cleanup instead of failing closed to the always-on OpenRouter contract.
    @Test
    func forbiddenAnthropicProviderRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(
                legacyEnabledField: true,
                cleanupProvider: "anthropic",
                writingStyle: "formal"
            ),
        ])

        let config = ConfigStore.load(from: defaults)

        #expect(config == .defaults)
        #expect(config.openRouterModel == Config.defaultOpenRouterModel)
    }

    /// Stated sensitivity: keep treating a forbidden OpenAI provider as active
    /// or disabled instead of failing closed to the OpenRouter default contract.
    @Test
    func forbiddenOpenAIProviderRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(cleanupProvider: "openai"),
        ])

        let config = ConfigStore.load(from: defaults)

        #expect(config == .defaults)
        #expect(config.openRouterModel == Config.defaultOpenRouterModel)
        #expect(config.cleanupConfig.model == Config.defaultOpenRouterModel)
    }

    /// Stated sensitivity: treat OpenRouter as an ad hoc string or forget its
    /// model field -> stored routed-cloud cleanup selection is rejected or falls
    /// back to a different provider.
    @Test
    func openRouterProviderAndModelDecodeFromCleanupConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(
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
            ConfigStore.defaultKey: try ConfigFixtures.configData(
                legacyEnabledField: false,
                openRouterModel: "openai/gpt-5.4-nano"
            ),
        ])

        let config = ConfigStore.load(from: defaults)

        #expect(config.openRouterModel == "openai/gpt-5.4-nano")
        #expect(config.cleanupConfig.model == "openai/gpt-5.4-nano")
    }

    /// Stated sensitivity: accept an unknown cleanup provider as active or as a
    /// user-off state -> the app silently preserves a forbidden cleanup contract.
    @Test
    func unknownCleanupProviderRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(cleanupProvider: "local-llm"),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
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

    /// Stated sensitivity: decoding persisted ASR backend from the Swift case
    /// name instead of the documented wire format must be rejected independently.
    @Test
    func swiftCaseBackendRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(backend: "whisperKit"),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// Stated sensitivity: decoding persisted writing style from the Swift case
    /// name instead of the documented wire format must be rejected independently.
    @Test
    func swiftCaseWritingStyleRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(writingStyle: "veryCasual"),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// Stated sensitivity: ignoring fixed v1 trigger accepts a value the app
    /// cannot execute.
    @Test
    func invalidFixedTriggerRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(trigger: "capslock"),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// Stated sensitivity: ignoring fixed v1 mode accepts a value the app cannot
    /// execute.
    @Test
    func invalidFixedModeRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(mode: "toggle"),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
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
                openRouterModel: "openai/gpt-5.4-nano",
                writingStyle: "formal"
            ),
        ])

        #expect(ConfigStore.load(from: defaults) == Config(
            language: .ru,
            keepWarmSeconds: 45,
            asrBackend: .whisperKit,
            asrModel: "large-v3-v20240930_turbo_632MB",
            openRouterModel: "openai/gpt-5.4-nano",
            writingStyle: .formal
        ))
    }

    /// Persisted configs from the abandoned Apple-Speech migration used backend
    /// "speechtranscriber" + model "system-dictation". Those legacy values MIGRATE
    /// to the WhisperKit turbo runtime on load (a mapping, NOT whole-config
    /// rejection): the single-case `AsrBackend`'s synthesized Codable cannot even
    /// represent "speechtranscriber", so the implementer must map the legacy string
    /// BEFORE raw-value matching. keepWarmSeconds RESETS to resident (nil) for any
    /// legacy value (legacy keepWarm meant Apple retention, not an idle window).
    /// Unrelated cleanup/style fields survive untouched.
    ///
    /// Anti-tautology: after migration asrBackend/asrModel/keepWarmSeconds ALL equal
    /// their new defaults (.whisperKit / turbo / nil), so asserting any of those
    /// alone is false-green — the BROKEN discard-to-defaults path satisfies them too.
    /// The load-bearing assertion is a NON-DEFAULT surviving sibling: `writingStyle:
    /// .formal` (≠ .casual default) and a non-default openRouterModel the user set.
    /// Stated sensitivity: reject-instead-of-migrate (whole config → defaults) → the
    /// non-default writingStyle/openRouterModel are lost → RED. Skip the model remap
    /// → asrModel stays "system-dictation" → RED.
    @Test
    func legacyAppleSpeechConfigMigratesToWhisperKit() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(
                keepWarmSeconds: 999,
                backend: "speechtranscriber",
                asrModel: "system-dictation",
                cleanupProvider: "openrouter",
                openRouterModel: "openai/gpt-6-nano",
                writingStyle: "formal"
            ),
        ])

        let config = ConfigStore.load(from: defaults)

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
            openRouterModel: "openai/gpt-5.4-nano"
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
