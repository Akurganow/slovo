import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// A cleanup model RETIRED from the catalog must be migrated on load, not
// kept flowing to OpenRouter as a stale id. Split from ConfigStoreTests to keep both
// files under the strict SwiftLint file_length gate.
@Suite("ConfigStore cleanup-model migration")
struct ConfigStoreCatalogMigrationTests {

    /// A persisted cleanup model that has been RETIRED from the catalog must
    /// MIGRATE to the catalog default on load — otherwise the stale id keeps
    /// flowing to OpenRouter and surfaces as a runtime apiError. This is a SPECIFIC
    /// stale-id migration, NOT a catch-all:
    /// user-chosen custom ids must still survive load unchanged (already guarded by
    /// ConfigStoreTests.saveRoundTripsOpenRouterModelWithoutProviderField), so the
    /// fix must migrate only known-retired ids, never every non-catalog id.
    ///
    /// Anti-tautology: the load-bearing assertions are NON-DEFAULT siblings the user
    /// set — writingStyle .formal (≠ .casual default) and keepWarmSeconds 45 (≠ nil
    /// default) — which a whole-config fallback to .defaults would destroy. Asserting
    /// only openRouterModel == default would false-green on a broken reject-to-
    /// defaults path.
    /// Stated sensitivity: keep the stored openRouterModel verbatim (no migration) →
    /// config.openRouterModel is the retired id, not the default → RED.
    @Test
    func retiredCleanupModelMigratesToCatalogDefault() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(
                keepWarmSeconds: 45,
                cleanupProvider: "openrouter",
                openRouterModel: "google/gemini-2.5-flash-lite",
                writingStyle: "formal"
            ),
        ])

        let config = ConfigStore.load(from: defaults)

        #expect(config.openRouterModel == Config.defaultOpenRouterModel,
                "a retired cleanup model must fall back to the catalog default, not keep flowing to OpenRouter")
        #expect(config.cleanupConfig.model == Config.defaultOpenRouterModel,
                "the migrated default must be the model the runtime cleanup request uses")
        // Non-default siblings a whole-config fallback to .defaults would lose,
        // proving the config decoded and ONLY the stale model was migrated.
        #expect(config.writingStyle == .formal)
        #expect(config.keepWarmSeconds == 45)
        #expect(config != .defaults)
    }

    @Test
    func formerDefaultMigratesFromLegacyCatalog() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(
                cleanupProvider: "openrouter",
                openRouterModel: "openai/gpt-5.4-nano"
            ),
        ])

        #expect(ConfigStore.load(from: defaults).openRouterModel == Config.defaultOpenRouterModel)
    }

    @Test
    func savedFormerDefaultRoundTripsAsCustomModel() throws {
        let defaults = FakeUserDefaults()
        var config = Config.defaults
        config.openRouterModel = "openai/gpt-5.4-nano"

        try ConfigStore.save(config, to: defaults)

        #expect(ConfigStore.load(from: defaults).openRouterModel == "openai/gpt-5.4-nano")
    }

    /// A catalog model replaced by a newer release of the same line moves to that
    /// release, never to the default: a user who picked DeepSeek stays on DeepSeek.
    /// Anti-tautology: the fixture's writingStyle .formal is a non-default sibling
    /// that a whole-config fallback to .defaults would lose.
    /// Stated sensitivity: drop a pair from the successor table, or send a replaced
    /// id to the default instead → the loaded model is not the successor → RED.
    @Test(arguments: [
        ("openai/gpt-5.6-luna", "openai/gpt-6-luna"),
        ("deepseek/deepseek-v4-flash", "deepseek/deepseek-v4.1-flash"),
        ("qwen/qwen3.6-flash", "qwen/qwen3.8-flash"),
    ])
    func replacedCatalogModelMigratesToItsSuccessor(stored: String, successor: String) throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(
                cleanupProvider: "openrouter",
                openRouterModel: stored,
                modelCatalogVersion: 1,
                writingStyle: "formal"
            ),
        ])

        let config = ConfigStore.load(from: defaults)

        #expect(config.openRouterModel == successor)
        #expect(config.writingStyle == .formal)
    }

    /// Stated sensitivity: apply the successor table whatever catalog version the
    /// config was saved under → the id the user entered after the update is
    /// replaced on the next load → RED.
    @Test
    func replacedModelSavedUnderCurrentCatalogRoundTripsAsCustomModel() throws {
        let defaults = FakeUserDefaults()
        var config = Config.defaults
        config.openRouterModel = "deepseek/deepseek-v4-flash"

        try ConfigStore.save(config, to: defaults)

        #expect(ConfigStore.load(from: defaults).openRouterModel == "deepseek/deepseek-v4-flash")
    }
}
