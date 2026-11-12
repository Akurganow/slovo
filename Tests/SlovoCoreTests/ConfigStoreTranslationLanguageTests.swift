import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The persisted translate target must default to "en" when absent, round-trip a
// supported code. "auto" or an unsupported code returns to the default in
// ConfigStoreRecoveryTests.
@Suite("ConfigStore translation target language")
struct ConfigStoreTranslationLanguageTests {
    /// C1 — an absent translationTargetLanguage decodes to "en", and the rest of the
    /// blob still decodes (not a silent fall-back to defaults).
    /// Green now. Stated sensitivity: change the absent-field default off "en" (e.g.
    /// `.ru`) → the target assert reddens; reset the whole config because the key is
    /// absent → `language` is `.auto`, not `.ru` → the language assert reddens.
    @Test
    func absentTranslationTargetDefaultsToEnglish() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(language: "ru"),
        ])

        let loaded = ConfigStore.load(from: defaults)
        #expect(loaded.translationTargetLanguage == .en)
        #expect(loaded.language == Language(rawValue: "ru"),
                "the blob must actually decode (a silent defaults fall-back would lose the ru language)")
    }

    /// C2 — a supported target code survives save→load.
    /// Green now. Stated sensitivity: stop encoding translationTargetLanguage in
    /// StoredConfig → the reload defaults to "en", not "ru" → RED.
    @Test
    func supportedTranslationTargetRoundTrips() throws {
        let defaults = FakeUserDefaults()
        var config = Config.defaults
        config.translationTargetLanguage = .ru
        try ConfigStore.save(config, to: defaults)

        #expect(ConfigStore.load(from: defaults).translationTargetLanguage == .ru)
    }
}
