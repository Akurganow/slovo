import AppKit

public extension MenuBarGlyph {
    /// Renders `glyph` as a menu-bar status image tinted for `tint`.
    ///
    /// The error tint is a NON-template red image: `NSStatusBarButton` paints
    /// template images in the system menu-bar color and ignores `contentTintColor`,
    /// which would silently drop the red. Normal glyphs stay template so the menu
    /// bar tints them to match the light or dark bar.
    ///
    /// Returns `nil` when the Glagolitic font is unavailable, so the caller can
    /// fall back to a system symbol.
    static func image(for glyph: Character, tint: MenuBarGlyphTint) -> NSImage? {
        guard let font = NSFont(name: "NotoSansGlagolitic-Regular", size: 16) else {
            return nil
        }
        let style = renderingStyle(for: tint)
        let text = NSAttributedString(
            string: String(glyph),
            attributes: [
                .font: font,
                .foregroundColor: style.color,
            ]
        )
        let textSize = text.size()
        let image = NSImage(size: NSSize(width: ceil(textSize.width), height: ceil(textSize.height)))
        image.lockFocus()
        text.draw(at: .zero)
        image.unlockFocus()
        image.isTemplate = style.isTemplate
        return image
    }

    // Color and template-ness are two facets of one per-tint decision — a template
    // image is re-tinted by the menu bar, discarding its color — so a new tint case
    // must revisit both; keep them in a single exhaustive switch.
    private static func renderingStyle(for tint: MenuBarGlyphTint) -> (color: NSColor, isTemplate: Bool) {
        switch tint {
        case .normal:
            return (.black, true)
        case .error:
            return (.systemRed, false)
        }
    }
}
