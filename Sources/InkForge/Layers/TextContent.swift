import AppKit

struct TextContent {
    var text: String
    var fontName: String
    var fontSize: CGFloat
    var isBold: Bool
    var isItalic: Bool
    var color: NSColor
    var position: CGPoint  // Canvas coordinates (top-left origin)

    func resolvedFont() -> NSFont {
        var font = NSFont(name: fontName, size: fontSize)
                   ?? .systemFont(ofSize: fontSize)
        let fm = NSFontManager.shared
        if isBold  { font = fm.convert(font, toHaveTrait: .boldFontMask) }
        if isItalic { font = fm.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    func attributedString() -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: resolvedFont(),
            .foregroundColor: color,
        ]
        return NSAttributedString(string: text, attributes: attrs)
    }

    /// Bounding rect of the rendered text in canvas coordinates (top-left origin).
    func boundingRect() -> CGRect {
        let size = attributedString().size()
        return CGRect(origin: position, size: size)
    }
}
