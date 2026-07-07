import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// A cleanup model RETIRED from the catalog must be migrated on load, not
// kept flowing to OpenRouter as a stale id. Split from ConfigStoreTests to keep both
// files under the strict SwiftLint file_length gate.
@Suite("ConfigStore cleanup-model migration")
struct ConfigStoreCatalogMigrationTests {

    /// A persisted cleanup model that has been RETIRED from the catalog (here the
    /// removed google/gemini-2.5-flash-lite) must MIGRATE to the catalog default on
    /// load — otherwise the stale id keeps flowing to OpenRouter and surfaces as a
    /// runtime apiError. This is a SPECIFIC stale-id migration, NOT a catch-all:
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
    /// config.openRouterModel is the retired gemini id, not the default → RED.
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
}
