extension PromptBuilder {
    /// Hand-kept: WhisperKit's language table is a dictionary, so the source order that lists the standard name first is lost,
    /// and the catalogue picks "Moldovan", "Haitian", "Letzeburgesch", "Panjabi". Two-script targets name the script.
    public static func translationTargetName(for code: String) -> String {
        promptTargetNames[code] ?? RecognitionLanguageCatalog.displayName(for: code) ?? code
    }

    private static let promptTargetNames: [String: String] = [
        "ro": "Romanian",
        "ht": "Haitian Creole",
        "lb": "Luxembourgish",
        "pa": "Punjabi, in Gurmukhi script",
        "zh": "Simplified Chinese",
        "sr": "Serbian, in Cyrillic script",
    ]
}
