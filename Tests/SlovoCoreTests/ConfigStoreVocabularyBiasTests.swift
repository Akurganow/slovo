import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The experimental vocabulary-bias switch lives in the persisted `asr` object and
// must decode OFF for every blob written before it existed — an experiment nobody
// opted into must never turn itself on at launch.
@Suite("ConfigStore vocabularyBias")
struct ConfigStoreVocabularyBiasTests {
    /// Stated sensitivity: default the absent field to `true` (`?? true`) → RED. The
    /// fixture omits the key, which is exactly what every shipped install stores.
    @Test
    func absentWireFieldDecodesOff() throws {
        let defaults = FakeUserDefaults()
        defaults.set(try ConfigFixtures.configData(), forKey: ConfigStore.defaultKey)

        #expect(ConfigStore.load(from: defaults).usesVocabularyBias == false)
        #expect(Config.defaults.usesVocabularyBias == false)
    }

    /// Pins the wire KEY and its place inside `asr` — a save/load round trip alone
    /// would pass with any key the two sides happen to agree on.
    /// Stated sensitivity: rename the coding key, or move it out of the `asr`
    /// object → the hand-written blob decodes off → RED.
    @Test
    func storedWireFieldInsideAsrDecodesOn() throws {
        let defaults = FakeUserDefaults()
        let blob: [String: Any] = [
            "language": "ru",
            "asr": ["backend": "whisperkit", "model": Config.defaultAsrModel, "vocabularyBias": true],
            "cleanup": ["enabled": true, "writingStyle": "casual"],
        ]
        defaults.set(try ConfigFixtures.encoded(blob), forKey: ConfigStore.defaultKey)

        #expect(ConfigStore.load(from: defaults).usesVocabularyBias == true)
    }

    /// Stated sensitivity: drop the field from the encoder, or from the `Config`
    /// built in `validated()` → the saved `true` comes back `false` → RED.
    @Test
    func saveLoadRoundTripPreservesOn() throws {
        let defaults = FakeUserDefaults()
        var config = Config()
        config.usesVocabularyBias = true

        try ConfigStore.save(config, to: defaults)

        #expect(ConfigStore.load(from: defaults).usesVocabularyBias == true)
    }
}
