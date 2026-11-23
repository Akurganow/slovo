import Testing

import SlovoCore

// The selector that fixes what one dictation reads once, from the one state.
@Suite("Dictation settings")
struct DictationSettingsTests {
    /// Stated sensitivity: `runsCleaner` taken from the stored preference alone
    /// (`config.cleanupEnabled`) → RED with the key absent; `cleanup` taken from
    /// `config.cleanupConfig` → RED on the same assertion.
    @Test
    func cleanupIsTheEffectiveConfigAndNeverTranslates() {
        var config = Config.defaults
        config.cleanupEnabled = true
        let state = AppState(config: config, isOpenRouterKeyPresent: false)
        let settings = state.dictationSettings
        #expect(settings.cleanup == state.effectiveCleanupConfig)
        #expect(!settings.cleanup.runsCleaner, "without a key a dictation must run raw")
        #expect(!settings.cleanup.translate, "translate is the hold's mode, set at clean time")
    }

    /// Stated sensitivity: `usesVocabularyBias` taken from the mute switch, or
    /// `mutesSystemAudio` from the bias switch → RED; the two differ here so a swap shows.
    @Test
    func muteAndBiasComeFromTheirOwnSwitches() {
        var config = Config.defaults
        config.mutesSystemAudioWhileDictating = false
        config.usesVocabularyBias = true
        let settings = AppState(config: config, isOpenRouterKeyPresent: true).dictationSettings
        #expect(!settings.mutesSystemAudio)
        #expect(settings.usesVocabularyBias)

        config.mutesSystemAudioWhileDictating = true
        config.usesVocabularyBias = false
        let flipped = AppState(config: config, isOpenRouterKeyPresent: true).dictationSettings
        #expect(flipped.mutesSystemAudio)
        #expect(!flipped.usesVocabularyBias)
    }

    /// Stated sensitivity: `recognitionLanguage` taken from `translationTargetLanguage`
    /// → RED (it would be `.en`).
    @Test
    func recognitionLanguageIsNotTheTranslationTarget() {
        var config = Config.defaults
        config.language = .ru
        config.translationTargetLanguage = .en
        let settings = AppState(config: config, isOpenRouterKeyPresent: true).dictationSettings
        #expect(settings.recognitionLanguage == .ru)
    }

    /// Stated sensitivity: a default of `true` for `Config.usesVocabularyBias` → RED.
    @Test
    func theDefaultsRunAnUnbiasedRecognizer() {
        let settings = AppState(config: .defaults, isOpenRouterKeyPresent: true).dictationSettings
        #expect(!settings.usesVocabularyBias)
    }
}
