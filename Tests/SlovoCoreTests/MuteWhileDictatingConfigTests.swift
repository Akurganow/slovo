import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The mute-while-dictating switch is a CAPTURE-stage setting: it defaults ON
// (exactly today's unconditional-mute behavior) and persists backward-compatibly,
// so pre-feature installs keep muting.
@Suite("Mute-while-dictating config")
struct MuteWhileDictatingConfigTests {
    /// AC1: the mute switch defaults ON, so a fresh install keeps today's
    /// unconditional-mute behavior.
    /// Stated sensitivity: flip the stored default to `false` → RED.
    @Test
    func defaultsToMutingWhileDictating() {
        #expect(Config.defaults.mutesSystemAudioWhileDictating == true)
    }

    /// AC2: the load-bearing wire-path test. Because the default is `true`, `false`
    /// is the ONLY value that can prove the field survives a save→load round-trip.
    /// Stated sensitivity: an implementation that never persists the field (or
    /// encodes it under the wrong key) reads back the `true` default, so a saved
    /// `false` returns `true` → RED.
    @Test
    func mutesFlagRoundTripsFalse() throws {
        let defaults = FakeUserDefaults()
        try ConfigStore.save(Config(mutesSystemAudioWhileDictating: false), to: defaults)

        #expect(ConfigStore.load(from: defaults).mutesSystemAudioWhileDictating == false)
    }

    /// AC2: backward compatibility. A persisted blob with the field ABSENT (every
    /// pre-feature install) must decode to the `true` default, never `false`.
    /// Stated sensitivity (two mutations, both reddened):
    /// (a) decode the absent wire field as `?? false` → mutes == false → RED.
    /// (b) a fixture blob that FAILS to decode → `ConfigStore.load` falls back to
    ///     `.defaults` (language .auto), so the language assert reddens. This closes
    ///     the mask where a default-fallback (mutes == true too) would otherwise
    ///     satisfy the mute assert for the WRONG reason — the field never decoded.
    @Test
    func absentMutesFieldDefaultsToTrue() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(),
        ])

        let loaded = ConfigStore.load(from: defaults)

        // The fixture encodes language "ru" (≠ the .auto default), proving the blob
        // actually decoded rather than falling back to defaults.
        #expect(loaded.language == .ru, "the fixture blob must actually decode, not fall back to defaults")
        #expect(loaded.mutesSystemAudioWhileDictating == true)
    }
}
