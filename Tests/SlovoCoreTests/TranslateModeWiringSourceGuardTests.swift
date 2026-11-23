import Foundation
import Testing

// No test target depends on the `slovo` executable, so this guard reads its menu source
// (comment-stripped, so a token surviving only in a comment cannot satisfy an assert).
@Suite("Translate mode wiring source guards")
struct TranslateModeWiringSourceGuardTests {
    /// The translate submenu renderer builds the recognition-language
    /// catalog (NO Auto row), checkmarks the selected code, and the select action
    /// writes the store's translate target.
    /// Stated sensitivity: drop the catalog or select wiring, or the store write →
    /// the matching positive `#expect` reddens; add an Auto row (`Language.auto` or
    /// a `"Auto"` tag) to the translate submenu → a negative `#expect` reddens.
    @Test
    func translateMenuRendererBuildsCatalogSubmenuWithoutAuto() throws {
        let source = try SourceText.code("Sources/slovo/AppDelegate+TranslateMenu.swift")
        #expect(source.contains("RecognitionLanguageCatalog.options"),
                "the submenu must be built from the recognition-language catalog")
        #expect(source.contains("selectTranslationLanguage"),
                "each row must target the select action")
        #expect(source.contains("$0.config.translationTargetLanguage ="),
                "selecting a language must write the store's translate target")
        #expect(source.contains(".state =") && source.contains(".on : .off"),
                "the selected row must be checkmarked (.state = ... .on : .off)")
        #expect(!source.contains("Language.auto"),
                "the translate submenu must not offer Auto (a translate target must be concrete)")
        #expect(!source.contains("\"Auto\""),
                "the translate submenu must not offer a hardcoded Auto row")
    }
}
