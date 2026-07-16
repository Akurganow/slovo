import Foundation
import Testing

import SlovoCore

// Guards the app wiring the SlovoCore renderer test cannot see: the executable
// `slovo` target is not importable, so these read its source to confirm each
// status's own tint reaches `MenuBarGlyph.image(for:tint:)` and that the app no
// longer hand-builds a template glyph image locally.
@Suite("Menu-bar glyph wiring")
struct MenuBarGlyphWiringSourceGuardTests {
    /// A failure status must render through the core error tint; a live-state glyph
    /// must render through the normal tint.
    ///
    /// Sensitivity: pass a fixed `.normal` tint for the status path (reverting the
    /// error glyph to a black template) → the error-path order check goes RED.
    @Test
    func statusGlyphRoutesStatusTintIntoCoreRenderer() throws {
        let glyphSource = try AppRuntimeSourceGuardTests.code("Sources/slovo/AppDelegate+Glyph.swift")
        let statusBody = try AppRuntimeSourceGuardTests.functionBody(named: "setStatusGlyph(status:", in: glyphSource)
        let stateBody = try AppRuntimeSourceGuardTests.functionBody(named: "setStatusGlyph(_ state:", in: glyphSource)

        #expect(AppRuntimeSourceGuardTests.containsInOrder([
            "MenuBarGlyph.image(for:",
            "tint: MenuBarGlyph.tint(forStatus: status)",
        ], in: statusBody))
        #expect(AppRuntimeSourceGuardTests.containsInOrder([
            "MenuBarGlyph.image(for:",
            "tint: .normal",
        ], in: stateBody))
    }

    /// Template management belongs to the core renderer, not the app: the menu bar
    /// re-tints template images and drops the error red, which was the original bug.
    ///
    /// Sensitivity: reintroduce an app-local `isTemplate` glyph builder → RED.
    @Test
    func appGlyphSourceDoesNotManageTemplateFlagLocally() throws {
        let glyphSource = try AppRuntimeSourceGuardTests.code("Sources/slovo/AppDelegate+Glyph.swift")

        #expect(!glyphSource.contains("isTemplate"))
    }
}
