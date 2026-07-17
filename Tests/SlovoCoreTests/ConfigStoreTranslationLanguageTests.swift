import Foundation
import Testing

import SlovoCore
import SlovoTestSupport

// The persisted translate target must default to "en" when absent, round-trip a
// supported code, and fail the WHOLE config closed for "auto" or an unsupported
// code — exactly like the recognition-language guard. The fail-closed cases are RED
// now: the pre-scaffolding decoder accepts any translationTargetLanguage without
// validation.
@Suite("ConfigStore translation target language")
struct ConfigStoreTranslationLanguageTests {
    /// C1 — an absent translationTargetLanguage decodes to "en", and the rest of the
    /// blob still decodes (not a silent fall-back to defaults).
    /// Green now. Stated sensitivity: change the absent-field default off "en" (e.g.
    /// `?? .ru`) → the target assert reddens; make the field a required decode (drop
    /// the `?? .en`) → the omitted-field blob throws and silently falls back to
    /// defaults, so `language` is `.auto`, not `.ru` → the language assert reddens.
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

    /// C3 — an "auto" translate target fails the whole config closed (a translate
    /// pass has no per-utterance detection; the target must be a concrete language).
    /// Passes on the correct code.
    /// Stated sensitivity: `.auto` is already rejected because
    /// `RecognitionLanguageCatalog.isSupported("auto")` is false (the explicit
    /// `!= .auto` guard is belt-and-suspenders, not what rejects it). The reddening
    /// mutation is removing the translation-target validation entirely (accept any
    /// code) → "auto" loads as a non-default config instead of `.defaults` → RED.
    @Test
    func autoTranslationTargetRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(translationTargetLanguage: "auto"),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }

    /// C4 — an unsupported translate target code fails the whole config closed,
    /// exactly like an unsupported recognition language.
    /// RED now: no target validation, so the blob loads non-default.
    /// Stated sensitivity: drop the `isSupported` target guard in `validated()` → RED.
    @Test
    func unsupportedTranslationTargetRejectsWholeConfig() throws {
        let defaults = FakeUserDefaults(dataByKey: [
            ConfigStore.defaultKey: try ConfigFixtures.configData(translationTargetLanguage: "xx"),
        ])

        #expect(ConfigStore.load(from: defaults) == .defaults)
    }
}
