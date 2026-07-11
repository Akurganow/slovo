import Testing

@testable import SlovoCore

// Pins the flagship RU+EN invariant at its enforcement point: the `.auto` sentinel
// must map to a nil WhisperKit code so the engine auto-detects and keeps mixed
// Russian+English working, while every pinned language maps to its own bare code.
// Inspection alone would let a future edit silently break the `.auto` sentinel; this
// test makes such an edit fail.
@Suite("WhisperKit language code mapping")
struct WhisperKitLanguageCodeTests {
    /// `.auto` → nil (auto-detect, mixed RU+EN); each pinned code → itself.
    /// Stated sensitivity: make the mapping always return `nil` → the ru/en/ja
    /// expectations go RED; make it always return `rawValue` → the `.auto`
    /// expectation goes RED (it would hand WhisperKit "auto" as a language and
    /// disable detection).
    @Test
    func autoDetectsAndPinnedCodesMapToThemselves() {
        #expect(Language.auto.whisperKitLanguageCode == nil)
        #expect(Language.ru.whisperKitLanguageCode == "ru")
        #expect(Language.en.whisperKitLanguageCode == "en")
        #expect(Language(rawValue: "ja").whisperKitLanguageCode == "ja")
    }
}
