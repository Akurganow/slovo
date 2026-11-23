import AppKit
import Testing

@testable import SlovoCore

@Suite("Menu-bar glyph image rendering")
struct MenuBarGlyphImageTests {
    /// The menu bar repaints a template image in its own color, so the failure
    /// glyph shows red only as a non-template image drawn in red.
    ///
    /// This pins the `.error` rendering style (`renderingStyle(for: .error)`) and
    /// that the image takes its template flag from it; the drawn pixels are not
    /// inspected.
    ///
    /// Sensitivity: make `renderingStyle(for: .error)` a template (the original
    /// bug), or give it any color but `systemRed` → RED.
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

    /// The update-ready Nash is drawn from the Glagolitic font, a macOS system font
    /// that Slovo does not bundle. This checks that the normal tint draws visible
    /// pixels: a font or codepoint that is not there makes `image(for:tint:)`
    /// return nil or draw nothing, and the caller would fall back to the mic symbol.
    /// Sensitivity: a nil image or zero opaque pixels → RED.
    @Test
    func updateReadyGlyphRendersVisiblePixels() throws {
        let image = try #require(MenuBarGlyph.image(for: MenuBarGlyph.updateReadyGlyph, tint: .normal))
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
