/// The settings one dictation reads once, when its recording begins, and keeps
/// until it ends.
public struct DictationSettings: Equatable, Sendable {
    /// Effective cleanup: model, style, target language, spell-hint switch and
    /// `runsCleaner` (preference and key present). `translate` is false in a
    /// snapshot; the orchestrator sets it per call at clean time from the
    /// hold's mode.
    public var cleanup: CleanupConfig
    public var mutesSystemAudio: Bool
    public var usesVocabularyBias: Bool
    public var recognitionLanguage: Language

    public init(
        cleanup: CleanupConfig,
        mutesSystemAudio: Bool,
        usesVocabularyBias: Bool,
        recognitionLanguage: Language
    ) {
        self.cleanup = cleanup
        self.mutesSystemAudio = mutesSystemAudio
        self.usesVocabularyBias = usesVocabularyBias
        self.recognitionLanguage = recognitionLanguage
    }
}

public extension AppState {
    /// The settings a dictation starting now would read.
    var dictationSettings: DictationSettings {
        DictationSettings(
            cleanup: effectiveCleanupConfig,
            mutesSystemAudio: config.mutesSystemAudioWhileDictating,
            usesVocabularyBias: config.usesVocabularyBias,
            recognitionLanguage: config.language
        )
    }
}

public extension AppStore {
    /// Reads `dictationSettings` from the live state on the main actor at call time.
    var dictationSettingsProvider: @Sendable () async -> DictationSettings {
        { [self] in await self.state.dictationSettings }
    }
}
