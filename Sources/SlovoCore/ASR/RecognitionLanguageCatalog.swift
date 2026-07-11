import WhisperKit

/// One offerable recognition language: a capitalized English display name and the
/// WhisperKit language code it persists as. `Identifiable` on `code` so a SwiftUI
/// `ForEach` over the catalog needs no explicit `id:`.
public struct RecognitionLanguageOption: Identifiable, Equatable, Sendable {
    public let displayName: String
    public let code: String

    public var id: String { code }

    public init(displayName: String, code: String) {
        self.displayName = displayName
        self.code = code
    }
}

/// The recognition languages Slovo offers, sourced programmatically from WhisperKit's
/// own `Constants` rather than a hardcoded table in Slovo. This is the ONLY place the
/// WhisperKit language table is read: the Settings picker builds its rows from
/// `options`, and config validation gates persisted codes through `isSupported`.
public enum RecognitionLanguageCatalog {
    /// The offered languages, sorted by display name.
    ///
    /// WhisperKit lists several English synonyms for some codes (e.g. "burmese" and
    /// "myanmar" both map to "my"). One entry per code is kept so a persisted code
    /// resolves to exactly one picker row; the canonical name is the shortest synonym
    /// (alphabetical tie-break), a deterministic pure transform of WhisperKit's data.
    public static let options: [RecognitionLanguageOption] = {
        var canonicalNameByCode: [String: String] = [:]
        for (name, code) in Constants.languages {
            guard let incumbent = canonicalNameByCode[code] else {
                canonicalNameByCode[code] = name
                continue
            }
            if (name.count, name) < (incumbent.count, incumbent) {
                canonicalNameByCode[code] = name
            }
        }
        return canonicalNameByCode
            .map { RecognitionLanguageOption(displayName: $0.value.capitalized, code: $0.key) }
            .sorted { $0.displayName < $1.displayName }
    }()

    /// Whether `code` is a recognition language WhisperKit supports. Backs the
    /// fail-closed config check: a persisted code outside this set is rejected.
    public static func isSupported(_ code: String) -> Bool {
        Constants.languageCodes.contains(code)
    }
}
