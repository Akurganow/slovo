import AppKit
import Testing

import SlovoCore

// Renders the real menu-bar glyph image and inspects its pixels. The menu bar
// tints TEMPLATE images itself (to the system menu-bar color) and ignores
// `NSStatusBarButton.contentTintColor`, so a failure glyph can only be red if the
// image is NON-template and already carries red. These tests observe that rendered
// reality rather than mirroring source strings.
@Suite("Menu-bar glyph image rendering")
struct MenuBarGlyphImageTests {
    private struct PixelStats {
        var opaque = 0
        var redDominant = 0
        var nearBlack = 0
    }

    /// The failure glyph must actually render red in the menu bar.
    ///
    /// Sensitivity: leave the error image as a template (`isTemplate == true`, the
    /// original bug) → the template assertion goes RED; draw the error glyph in
    /// black → the red-pixel assertions go RED (0 red-dominant, every pixel
    /// near-black); draw it in any warm-but-not-red color such as orange → the
    /// green-ceiling in the classifier rejects it and `redDominant` drops below
    /// `opaque` → RED.
    @Test
    func errorGlyphRendersAsNonTemplateRedImage() throws {
        let onu: Character = "\u{2C11}"
        let image = try #require(MenuBarGlyph.image(for: onu, tint: .error))

        #expect(image.isTemplate == false)

        let stats = try Self.pixelStats(of: image)
        try #require(stats.opaque > 0, "the glyph must draw visible pixels")
        #expect(stats.redDominant == stats.opaque, "every drawn pixel must read as red")
        #expect(stats.nearBlack == 0, "no drawn pixel may be black")
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

    private static func pixelStats(of image: NSImage) throws -> PixelStats {
        let tiff = try #require(image.tiffRepresentation, "image must be rasterizable")
        let rep = try #require(NSBitmapImageRep(data: tiff), "image must decode to a bitmap")
        var stats = PixelStats()
        for row in 0..<rep.pixelsHigh {
            for column in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: column, y: row), color.alphaComponent > 0.5 else { continue }
                stats.opaque += 1
                let red = color.redComponent
                let green = color.greenComponent
                let blue = color.blueComponent
                if red > green + 0.2 && red > blue + 0.2 && green < 0.35 && blue < 0.35 {
                    stats.redDominant += 1
                }
                if max(red, green, blue) < 0.3 { stats.nearBlack += 1 }
            }
        }
        return stats
    }
}
