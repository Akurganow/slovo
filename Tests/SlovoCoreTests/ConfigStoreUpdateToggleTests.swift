import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The automatic-update preference on the persisted config wire: round-trip,
// key presence, and the backward-compat default for configs stored before the
// field existed. A focused sibling of ConfigStoreTests, which sits at the
// file_length cap.
@Suite("ConfigStore update toggle")
struct ConfigStoreUpdateToggleTests {
    /// OFF must survive the save→load round trip; the stored preference is what
    /// gates the whole update pipeline at the next launch.
    /// Stated sensitivity: leave the field off the persistence wire (encode or
    /// decode side) → load reads the default `true` → RED.
    @Test
    func automaticallyInstallsUpdatesRoundTripsOff() throws {
        let defaults = FakeUserDefaults()
        var config = Config.defaults
        config.automaticallyInstallsUpdates = false

        try ConfigStore.save(config, to: defaults)

        #expect(ConfigStore.load(from: defaults).automaticallyInstallsUpdates == false)
    }

    /// The persisted JSON must carry the key explicitly, so the stored blob is
    /// self-describing and the OFF state is a value, not an absence.
    /// Stated sensitivity: drop the field from `StoredConfig`, or encode it only
    /// when it differs from its default → the saved default-valued blob has no such
    /// key → RED.
    @Test
    func savedConfigCarriesTheUpdateKeyOnTheWire() throws {
        let defaults = FakeUserDefaults()

        try ConfigStore.save(.defaults, to: defaults)

        let data = try #require(defaults.data(forKey: ConfigStore.defaultKey))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["automaticallyInstallsUpdates"] as? Bool == true)
    }

    /// Backward compat: a config stored BEFORE the field existed decodes with
    /// updates ON and every other stored field intact — existing users keep
    /// their settings and gain silent updates.
    /// Stated sensitivity: default the absent field to `false`, or reset the WHOLE
    /// config because a key is absent → updates read off, or the language pin
    /// (`.ru` ≠ default `.auto`) is lost → RED.
    /// Born green on the current tree — flagged for the mutation demonstration.
    @Test
    func legacyConfigWithoutTheKeyDefaultsToOnKeepingOtherFields() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(),
        ])

        let loaded = ConfigStore.load(from: defaults)
        #expect(loaded.automaticallyInstallsUpdates == true)
        #expect(loaded.language == .ru, "the legacy blob's other fields must survive the missing update key")
    }
}
