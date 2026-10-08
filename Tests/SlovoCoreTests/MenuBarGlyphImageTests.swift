import AppKit
import Testing

@testable import SlovoCore

@Suite("Menu-bar glyph image rendering")
struct MenuBarGlyphImageTests {
    /// The menu bar repaints a template image in its own color, so the failure
    /// glyph shows red only as a non-template image drawn in red.
    ///
    /// Sensitivity: leave the error image as a template (the original bug) → RED;
    /// draw the error glyph in any color but `systemRed` → RED.
    @Test
    func errorGlyphIsNonTemplateSystemRed() throws {
        let style = MenuBarGlyph.renderingStyle(for: .error)
        #expect(style.color == .systemRed)
        #expect(style.isTemplate == false)

        let image = try #require(MenuBarGlyph.image(for: "\u{2C11}", tint: .error))
        #expect(image.isTemplate == false)
    }

    /// Non-error glyphs stay template so the menu bar tints them to match the
    /// light/dark bar.
    ///
    /// Sensitivity: render normal glyphs as non-template (breaking light/dark
    /// adaptivity) → this goes RED.
    @Test
    func normalGlyphStaysTemplateForThemeAdaptivity() throws {
        let idle = MenuBarGlyph.forState(.idle)
        let image = try #require(MenuBarGlyph.image(for: idle, tint: .normal))

        #expect(image.isTemplate == true)
    }

    /// A non-error STATUS glyph (e.g. preparing the speech model) also renders
    /// template — the status overload's normal branch, not only the state overload.
    ///
    /// Sensitivity: give the normal-tinted status glyph a non-template image
    /// (breaking light/dark adaptivity for that path) → this goes RED.
    @Test
    func normalStatusGlyphStaysTemplate() throws {
        let status = StatusMessage.preparingSpeechModel
        let glyph = try #require(MenuBarGlyph.forStatus(status))
        let image = try #require(MenuBarGlyph.image(for: glyph, tint: MenuBarGlyph.tint(forStatus: status)))

        #expect(image.isTemplate == true)
    }

    /// The update-ready Nash must really exist in the bundled Glagolitic font and
    /// render as a visible template image — a missing codepoint would silently
    /// fall back to the mic symbol.
    /// Sensitivity: a codepoint absent from the font (renderer returns nil or
    /// zero pixels), or a non-template image → RED.
    @Test
    func updateReadyGlyphRendersVisibleTemplatePixels() throws {
        let image = try #require(MenuBarGlyph.image(for: MenuBarGlyph.updateReadyGlyph, tint: .normal))
        #expect(image.isTemplate == true)
        #expect(try Self.opaquePixelCount(of: image) > 0, "Nash must draw visible pixels")
    }

    private static func opaquePixelCount(of image: NSImage) throws -> Int {
        let tiff = try #require(image.tiffRepresentation, "image must be rasterizable")
        let rep = try #require(NSBitmapImageRep(data: tiff), "image must decode to a bitmap")
        var count = 0
        for row in 0..<rep.pixelsHigh {
            for column in 0..<rep.pixelsWide where (rep.colorAt(x: column, y: row)?.alphaComponent ?? 0) > 0.5 {
                count += 1
            }
        }
        return count
    }
}
