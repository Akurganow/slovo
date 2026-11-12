import Foundation
import Testing

import SlovoCore

// Guards the app wiring the SlovoCore renderer test cannot see. No test target depends on
// the `slovo` executable, so these read its source to confirm each status's own tint
// reaches `MenuBarGlyph.image(for:tint:)` and that the app builds no template glyph image
// locally.
@Suite("Menu-bar glyph wiring")
struct MenuBarGlyphWiringSourceGuardTests {
    /// A failure status must render through the core error tint; a live-state glyph
    /// must render through the normal tint.
    ///
    /// Sensitivity: pass a fixed `.normal` tint for the status path (reverting the
    /// error glyph to a black template) → the error-path order check goes RED.
    @Test
    func statusGlyphRoutesStatusTintIntoCoreRenderer() throws {
        let glyphSource = try SourceText.code("Sources/slovo/AppDelegate+Glyph.swift")
        let statusBody = try SourceText.functionBody(named: "setStatusGlyph(status:", in: glyphSource)
        let stateBody = try SourceText.functionBody(named: "setStatusGlyph(_ state:", in: glyphSource)

        #expect(SourceText.containsInOrder([
            "MenuBarGlyph.image(for:",
            "tint: MenuBarGlyph.tint(forStatus: status)",
        ], in: statusBody))
        #expect(SourceText.containsInOrder([
            "MenuBarGlyph.image(for:",
            "tint: .normal",
        ], in: stateBody))
    }

    /// Template management belongs to the core renderer, not the app: the menu bar
    /// re-tints template images, which drops the error red.
    ///
    /// Sensitivity: add an app-local `isTemplate` glyph builder → RED.
    @Test
    func appGlyphSourceDoesNotManageTemplateFlagLocally() throws {
        let glyphSource = try SourceText.code("Sources/slovo/AppDelegate+Glyph.swift")

        #expect(!glyphSource.contains("isTemplate"))
    }
}
