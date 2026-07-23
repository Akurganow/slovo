import Foundation
import Testing

// App-target menu/settings wiring is not unit-importable, so these guards scan its
// source (comment-stripped, so a token surviving only in a comment cannot satisfy an
// assert). They pin the Round-2 translate-mode wiring named in the lead's wiring
// spec. All RED now: the wiring text is absent (and `AppDelegate+TranslateMenu.swift`
// does not exist yet, so its guard reads as empty and its positive asserts fail).
@Suite("Translate mode wiring source guards")
struct TranslateModeWiringSourceGuardTests {

    /// G-MENU-1 — the translate submenu renderer builds the recognition-language
    /// catalog (NO Auto row), checkmarks the selected code, and wires the select
    /// action into `applyTranslationLanguage`.
    /// Stated sensitivity: drop the catalog/select/apply wiring → the matching
    /// positive `#expect` reddens; add an Auto row (`Language.auto` or a `"Auto"`
    /// tag) to the translate submenu → a negative `#expect` reddens.
    @Test
    func translateMenuRendererBuildsCatalogSubmenuWithoutAuto() {
        let source = Self.code("Sources/slovo/AppDelegate+TranslateMenu.swift")
        #expect(source.contains("RecognitionLanguageCatalog.options"),
                "the submenu must be built from the recognition-language catalog")
        #expect(source.contains("selectTranslationLanguage"),
                "each row must target the select action")
        #expect(source.contains("applyTranslationLanguage"),
                "selecting a language must route into applyTranslationLanguage")
        #expect(source.contains(".state =") && source.contains(".on : .off"),
                "the selected row must be checkmarked (.state = ... .on : .off)")
        #expect(!source.contains("Language.auto"),
                "the translate submenu must not offer Auto (a translate target must be concrete)")
        #expect(!source.contains("\"Auto\""),
                "the translate submenu must not offer a hardcoded Auto row")
    }

    /// G-MENU-2 — applying a translate language is a LIVE apply (persist + rebuild
    /// the status menu + push the cleanup config), never a pipeline rebuild — mirrors
    /// `applyCleanupModel`.
    /// Stated sensitivity: drop `installStatusMenu()` or the live push through the
    /// effective-config funnel (`pushEffectiveCleanupConfig()`) → the positive
    /// `#expect` reddens; route through `startPipeline`/`retrySetup` (an ASR rebuild)
    /// → a negative `#expect` reddens.
    @Test
    func applyTranslationLanguageAppliesLiveWithoutRebuild() {
        let delegate = Self.code("Sources/slovo/Settings/AppDelegate+Settings.swift")
        let body = Self.functionBody(named: "applyTranslationLanguage", in: delegate)
        #expect(body.contains("installStatusMenu()"),
                "applyTranslationLanguage must rebuild the status menu to recheck the selected row")
        #expect(body.contains("pushEffectiveCleanupConfig()"),
                "applyTranslationLanguage must push the effective cleanup config live through the funnel")
        #expect(!body.contains("startPipeline"),
                "applyTranslationLanguage must not rebuild the pipeline")
        #expect(!body.contains("retrySetup"),
                "applyTranslationLanguage must not rebuild the pipeline via retrySetup")
    }

    /// G-SETTINGS-1 — the Cleanup pane hosts a translation picker driven by the
    /// catalog (NO Auto row), wired to the setter, and re-seeded on appear.
    /// Stated sensitivity: drop the setter/catalog/reseed → the positive `#expect`
    /// reddens; add an Auto option (`Language.auto` / a `"Auto"` tag) → a negative
    /// `#expect` reddens.
    @Test
    func cleanupPaneHostsTranslationPicker() {
        let cleanup = Self.code("Sources/slovo/Settings/CleanupSettingsPane.swift")
        #expect(cleanup.contains("setTranslationLanguage("),
                "the translation picker must drive actions.setTranslationLanguage")
        #expect(cleanup.contains("RecognitionLanguageCatalog.options"),
                "the translation picker must be built from the recognition-language catalog")
        #expect(cleanup.contains("translationTargetLanguage"),
                "the pane must re-seed the translation language from currentConfig().translationTargetLanguage")
        #expect(!cleanup.contains("Language.auto"),
                "the translation picker must not offer Auto")
        #expect(!cleanup.contains("\"Auto\""),
                "the translation picker must not offer a hardcoded Auto row")
    }

    /// G-SETTINGS-2 — the SettingsActions seam exposes the translation-language
    /// setter the pane calls.
    /// Stated sensitivity: drop the seam method → the pane cannot be wired → RED.
    @Test
    func settingsActionsExposesTranslationLanguageSetter() {
        let actions = Self.code("Sources/slovo/Settings/SettingsActions.swift")
        #expect(actions.contains("func setTranslationLanguage("),
                "SettingsActions must declare setTranslationLanguage")
    }

    // MARK: - Source scanning helpers (missing file / missing function → "", so an
    // absent-wiring guard fails on its positive assert rather than throwing).

    private static func code(_ relativePath: String) -> String {
        guard let raw = try? String(contentsOf: packageRoot.appending(path: relativePath), encoding: .utf8) else {
            return ""
        }
        return strippingComments(from: raw)
    }

    private static func functionBody(named name: String, in source: String) -> String {
        guard let signature = source.range(of: "func \(name)"),
              let openBrace = functionOpeningBrace(after: signature.lowerBound, in: source)
        else {
            return ""
        }
        return blockBody(from: openBrace, in: source)
    }

    private static func blockBody(from openBrace: String.Index, in source: String) -> String {
        var depth = 0
        var index = openBrace
        while index < source.endIndex {
            if source[index] == "{" {
                depth += 1
            } else if source[index] == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[openBrace...index])
                }
            }
            index = source.index(after: index)
        }
        return String(source[openBrace...])
    }

    private static func functionOpeningBrace(after start: String.Index, in source: String) -> String.Index? {
        var index = start
        var parenDepth = 0
        while index < source.endIndex {
            if source[index] == "(" {
                parenDepth += 1
            } else if source[index] == ")" {
                parenDepth -= 1
            } else if source[index] == "{", parenDepth == 0 {
                return index
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static func strippingComments(from source: String) -> String {
        var output = ""
        var index = source.startIndex
        var inLineComment = false, inBlockComment = false, inString = false
        while index < source.endIndex {
            let character = source[index]
            let nextIndex = source.index(after: index)
            let next = nextIndex < source.endIndex ? source[nextIndex] : "\0"
            if inLineComment {
                if character == "\n" { inLineComment = false; output.append(character) }
            } else if inBlockComment {
                if character == "*" && next == "/" { inBlockComment = false; index = nextIndex }
            } else if inString {
                output.append(character)
                if character == "\"" { inString = false }
            } else if character == "/" && next == "/" {
                inLineComment = true; index = nextIndex
            } else if character == "/" && next == "*" {
                inBlockComment = true; index = nextIndex
            } else {
                output.append(character)
                if character == "\"" { inString = true }
            }
            index = source.index(after: index)
        }
        return output
    }

    private static var packageRoot: URL {
        let testFile = URL(fileURLWithPath: "\(#filePath)")
        return testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
