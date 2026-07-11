import Testing

import SlovoCore

// The recognition-language catalog is a pure transform of WhisperKit's own language
// table: the full supported set, one row per code, capitalized, and sorted for the
// Settings picker. These pin that shape without re-hardcoding the table here.
@Suite("Recognition language catalog")
struct RecognitionLanguageCatalogTests {
    /// The catalog exposes WhisperKit's full set, not a handful of hardcoded rows.
    /// Stated sensitivity: return a fixed short list (or an empty array) → the count
    /// drops below 50 → RED.
    @Test
    func catalogIsNonTriviallyLarge() {
        #expect(RecognitionLanguageCatalog.options.count >= 50)
    }

    /// Russian and English appear with their capitalized display names and codes.
    /// Stated sensitivity: drop the `.capitalized` mapping → the names are "russian"/
    /// "english" and neither tuple matches → RED; emit a wrong code → RED.
    @Test
    func catalogContainsRussianAndEnglish() {
        let options = RecognitionLanguageCatalog.options
        #expect(options.contains { $0.displayName == "Russian" && $0.code == "ru" })
        #expect(options.contains { $0.displayName == "English" && $0.code == "en" })
    }

    /// Every display name starts with an uppercase letter.
    /// Stated sensitivity: drop the `.capitalized` mapping → WhisperKit's names are
    /// lowercase, so at least one entry's first character is not uppercase → RED.
    @Test
    func displayNamesAreCapitalized() {
        for option in RecognitionLanguageCatalog.options {
            #expect(option.displayName.first?.isUppercase == true)
        }
    }

    /// Options are ordered by display name for a predictable picker.
    /// Stated sensitivity: remove the `.sorted` step → dictionary iteration order is
    /// unspecified and effectively unsorted → RED.
    @Test
    func optionsAreSortedByDisplayName() {
        let names = RecognitionLanguageCatalog.options.map(\.displayName)
        #expect(names == names.sorted())
    }

    /// Each code appears once, so a persisted code maps to exactly one picker row.
    /// Stated sensitivity: drop the per-code dedup (map every WhisperKit name→code
    /// pair) → synonyms such as "burmese"/"myanmar" both yield code "my", a duplicate
    /// → RED.
    @Test
    func eachCodeAppearsOnce() {
        let codes = RecognitionLanguageCatalog.options.map(\.code)
        #expect(Set(codes).count == codes.count)
    }

    /// `isSupported` mirrors WhisperKit's code set.
    /// Stated sensitivity: hardcode `isSupported` to always return true → the "xx"
    /// case goes RED; always false → the "ru" case goes RED.
    @Test
    func isSupportedReflectsWhisperKitCodes() {
        #expect(RecognitionLanguageCatalog.isSupported("ru"))
        #expect(RecognitionLanguageCatalog.isSupported("en"))
        #expect(!RecognitionLanguageCatalog.isSupported("xx"))
    }
}
