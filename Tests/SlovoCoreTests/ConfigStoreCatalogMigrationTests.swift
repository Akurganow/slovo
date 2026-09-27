import Foundation
import Testing

@testable import SlovoCore
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

    /// Stated sensitivity: follow one replacement instead of the whole chain →
    /// gpt-5.4-nano lands on gpt-5.6-luna, not the default → RED.
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

    /// `.formal` catches a whole-config fallback to `.defaults`.
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
                writingStyle: "formal"
            ),
        ])

        let config = ConfigStore.load(from: defaults)

        #expect(config.openRouterModel == successor)
        #expect(config.writingStyle == .formal)
    }

    /// Earlier builds stored `modelCatalogVersion`; a config carrying it migrates too.
    /// Stated sensitivity: skip replacements for a config saved under catalog
    /// version 2 → the replaced id stays → RED.
    @Test
    func replacedModelMigratesWhateverCatalogVersionWasSaved() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(
                cleanupProvider: "openrouter",
                openRouterModel: "qwen/qwen3.6-flash",
                modelCatalogVersion: 2
            ),
        ])

        #expect(ConfigStore.load(from: defaults).openRouterModel == "qwen/qwen3.8-flash")
    }

    /// Stated sensitivity: point a successor outside the catalog, chain two ids
    /// into a cycle, or keep a replaced id in the catalog → RED.
    @Test
    func everyReplacedModelResolvesToACatalogModel() {
        let catalog = Set(CleanupModelCatalog.options.map(\.id))
        let successors = ConfigStore.openRouterModelSuccessors

        #expect(catalog.isDisjoint(with: successors.keys))
        for replaced in successors.keys {
            var model = replaced
            for _ in successors.indices {
                model = successors[model] ?? model
            }
            #expect(catalog.contains(model), "\(replaced) resolves to \(model), outside the catalog")
        }
    }
}
