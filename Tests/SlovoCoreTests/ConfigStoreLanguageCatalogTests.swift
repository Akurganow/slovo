import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The recognition language now spans WhisperKit's full catalog. A supported code
// (including exotic ones) must persist and reload intact; an unsupported code must
// fail the whole config closed, exactly like an unknown backend or trigger.
@Suite("ConfigStore recognition language catalog")
struct ConfigStoreLanguageCatalogTests {
    /// An exotic-but-supported code survives save→load.
    /// Stated sensitivity: gate acceptance to only auto/ru/en → "ja" is rejected, the
    /// config falls back to defaults, and the reloaded language is `.auto`, not "ja"
    /// → RED.
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

    /// A persisted code outside WhisperKit's catalog fails the whole config closed.
    /// Stated sensitivity: drop the catalog guard in `validated()` → "xx" decodes as
    /// a live Language and the otherwise-valid blob loads as a non-default config
    /// instead of `.defaults` → RED.
    @Test
    func unsupportedLanguageRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(language: "xx"),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }
}
