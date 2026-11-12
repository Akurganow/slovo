import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The recognition language now spans WhisperKit's full catalog. A supported code
// (including exotic ones) must persist and reload intact. An unsupported code
// returns to the default in ConfigStoreRecoveryTests.
@Suite("ConfigStore recognition language catalog")
struct ConfigStoreLanguageCatalogTests {
    /// An exotic-but-supported code survives save→load.
    /// Stated sensitivity: gate acceptance to only auto/ru/en → "ja" is unreadable, and
    /// the reloaded language is `.auto`, not "ja" → RED.
    @Test
    func supportedExoticLanguageRoundTrips() throws {
        let defaults = FakeUserDefaults()
        var config = Config.defaults
        config.language = Language(rawValue: "ja")
        try ConfigStore.save(config, to: defaults)

        #expect(ConfigStore.load(from: defaults).language == Language(rawValue: "ja"))
    }

    /// The legacy codes still round-trip unchanged.
    /// Stated sensitivity: break the bare-string wire (encode a keyed object) → the
    /// reload no longer equals the saved legacy value → RED.
    @Test
    func legacyLanguagesRoundTrip() throws {
        for language in [Language.auto, .ru, .en] {
            let defaults = FakeUserDefaults()
            var config = Config.defaults
            config.language = language
            try ConfigStore.save(config, to: defaults)

            #expect(ConfigStore.load(from: defaults).language == language)
        }
    }
}
