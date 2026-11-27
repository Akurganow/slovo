extension PromptBuilder {
    /// The name the translate directive gives a target: the script-qualified name where a language
    /// has two scripts, else the standard name, else the code.
    public static func translationTargetName(for code: String) -> String {
        scriptTargetNames[code] ?? standardLanguageName(for: code) ?? code
    }

    /// The standard English name of a language for the prompt, else the catalogue's name, else nil.
    /// The catalogue keeps WhisperKit's shortest synonym ("Moldovan" for ro), so the prompt names the
    /// standard language here; the translate target also names the script where a language has two.
    static func standardLanguageName(for code: String) -> String? {
        standardNames[code] ?? RecognitionLanguageCatalog.displayName(for: code)
    }

    private static let standardNames: [String: String] = [
        "ro": "Romanian",
        "ht": "Haitian Creole",
        "lb": "Luxembourgish",
        "pa": "Punjabi",
    ]

    private static let scriptTargetNames: [String: String] = [
        "zh": "Simplified Chinese",
        "sr": "Serbian, in Cyrillic script",
        "pa": "Punjabi, in Gurmukhi script",
    ]
}
