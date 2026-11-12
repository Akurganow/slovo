import Foundation
import Testing

// App-target menu/settings wiring is not unit-importable, so these guards scan its
// source (comment-stripped, so a token surviving only in a comment cannot satisfy an
// assert). They pin the translate-mode wiring.
@Suite("Translate mode wiring source guards")
struct TranslateModeWiringSourceGuardTests {

    /// G-MENU-1 — the translate submenu renderer builds the recognition-language
    /// catalog (NO Auto row), checkmarks the selected code, and the select action
    /// writes the store's translate target.
    /// Stated sensitivity: drop the catalog or select wiring, or the store write →
    /// the matching positive `#expect` reddens; add an Auto row (`Language.auto` or
    /// a `"Auto"` tag) to the translate submenu → a negative `#expect` reddens.
    @Test
    func translateMenuRendererBuildsCatalogSubmenuWithoutAuto() {
        let source = Self.code("Sources/slovo/AppDelegate+TranslateMenu.swift")
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

    /// G-SETTINGS-1 — the Cleanup pane hosts a translation picker driven by the
    /// catalog (NO Auto row) and bound to the store.
    /// Stated sensitivity: drop the binding or the catalog → a positive `#expect`
    /// reddens; add an Auto option (`Language.auto` / a `"Auto"` tag) → a negative
    /// `#expect` reddens.
    @Test
    func cleanupPaneHostsTranslationPicker() {
        let cleanup = Self.code("Sources/slovo/Settings/CleanupSettingsPane.swift")
        #expect(cleanup.contains(#"store.binding(\.translationTargetLanguage)"#),
                "the translation picker must bind the store's translate target")
        #expect(cleanup.contains("RecognitionLanguageCatalog.options"),
                "the translation picker must be built from the recognition-language catalog")
        #expect(!cleanup.contains("Language.auto"),
                "the translation picker must not offer Auto")
        #expect(!cleanup.contains("\"Auto\""),
                "the translation picker must not offer a hardcoded Auto row")
    }

    // MARK: - Source scanning helpers (a missing file → "", so an absent-wiring
    // guard fails on its positive assert rather than throwing).

    private static func code(_ relativePath: String) -> String {
        guard let raw = try? SourceText.read(relativePath) else {
            return ""
        }
        return SourceText.strippingComments(from: raw)
    }
}
