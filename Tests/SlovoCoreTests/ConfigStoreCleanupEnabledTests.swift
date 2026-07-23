import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The `cleanup.enabled` wire field was decoded-and-discarded (always re-encoded
// `true`) by every shipped version, so absent-or-true blobs must stay ON and a
// stored `false` must survive a round trip.
@Suite("ConfigStore cleanupEnabled")
struct ConfigStoreCleanupEnabledTests {
    /// Stated sensitivity: restore the discard-decode (`_ = decodeIfPresent`) or
    /// drop `cleanupEnabled` from `validated()` → this reads `true` → RED.
    @Test
    func storedFalseDecodesOff() throws {
        let defaults = FakeUserDefaults()
        defaults.set(try ConfigFixtures.configData(legacyEnabledField: false), forKey: ConfigStore.defaultKey)

        #expect(ConfigStore.load(from: defaults).cleanupEnabled == false)
    }

    /// Stated sensitivity: default the new field to `false` anywhere on the
    /// decode/default path → RED.
    @Test
    func legacyTrueBlobAndFreshDefaultsStayOn() throws {
        let defaults = FakeUserDefaults()
        defaults.set(try ConfigFixtures.configData(legacyEnabledField: true), forKey: ConfigStore.defaultKey)

        #expect(ConfigStore.load(from: defaults).cleanupEnabled == true)
        #expect(Config.defaults.cleanupEnabled == true)
    }

    /// Stated sensitivity: keep encoding the constant `true` (today's encoder) →
    /// the saved `false` comes back `true` → RED.
    @Test
    func saveLoadRoundTripPreservesOff() throws {
        let defaults = FakeUserDefaults()
        var config = Config()
        config.cleanupEnabled = false

        try ConfigStore.save(config, to: defaults)

        #expect(ConfigStore.load(from: defaults).cleanupEnabled == false)
    }
}
