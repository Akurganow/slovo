import AppKit

extension AppDelegate {
    static func menuBarGlyphImage(_ glyph: Character) -> NSImage? {
        guard let font = NSFont(name: "NotoSansGlagolitic-Regular", size: 16) else {
            return nil
        }
        let text = NSAttributedString(
            string: String(glyph),
            attributes: [
                .font: font,
                .foregroundColor: NSColor.black,
            ]
        )
        let textSize = text.size()
        let image = NSImage(size: NSSize(width: ceil(textSize.width), height: ceil(textSize.height)))
        image.lockFocus()
        text.draw(at: .zero)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
