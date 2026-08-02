import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// Sound Cues is one persisted boolean shared by Settings, the dropdown, and the
// running cue controller. Existing installs gain the accessibility feedback on.
@Suite("Dictation sound cue config")
struct DictationSoundCueConfigTests {
    /// Sensitivity: changing the fresh-install default to off makes this red.
    @Test
    func defaultsOn() {
        #expect(Config.defaults.playsDictationSoundCues)
    }

    /// Sensitivity: omitting or misnaming the JSON field makes an explicit false
    /// reload as the true default, and omitting it from encode removes the key.
    @Test
    func explicitOffRoundTripsOnTheNamedWireKey() throws {
        let defaults = FakeUserDefaults()
        var config = Config.defaults
        config.playsDictationSoundCues = false

        try ConfigStore.save(config, to: defaults)

        #expect(!ConfigStore.load(from: defaults).playsDictationSoundCues)
        let data = try #require(defaults.data(forKey: ConfigStore.defaultKey))
        #expect(String(decoding: data, as: UTF8.self).contains(#""playsDictationSoundCues":false"#),
                "the explicit off preference must use the pinned JSON key")
    }

    /// Sensitivity: decoding the missing field as false disables cues on every
    /// pre-feature install; requiring it rejects the fixture and loses keep-warm.
    @Test
    func legacyConfigWithoutTheWireKeyDefaultsOnWithoutResettingOtherFields() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(keepWarmSeconds: 45),
        ])

        let loaded = ConfigStore.load(from: defaults)

        #expect(loaded.playsDictationSoundCues)
        #expect(loaded.keepWarmSeconds == 45, "the legacy blob must decode instead of falling back to all defaults")
    }
}
