import AppKit

extension NSColor {
    // Backgrounds
    static let inkBg        = NSColor(red: 0.14, green: 0.14, blue: 0.15, alpha: 1)   // #242426 canvas surround
    static let inkPanel     = NSColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 1)   // #2E2E30 toolbar/status/sidebar
    static let inkPanelAlt  = NSColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 1)   // #383839 layer panel/color picker
    static let inkBtnBg     = NSColor(red: 0.24, green: 0.24, blue: 0.26, alpha: 1)   // #3D3D42 button backgrounds

    // Borders
    static let inkBorder    = NSColor(red: 0.30, green: 0.30, blue: 0.32, alpha: 1)   // #4D4D52

    // Text
    static let inkText      = NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)   // #F2F2F2 primary
    static let inkTextDim   = NSColor(red: 0.70, green: 0.70, blue: 0.72, alpha: 1)   // #B3B3B8 secondary
    static let inkTextMuted = NSColor(red: 0.50, green: 0.50, blue: 0.52, alpha: 1)   // #808085 tertiary

    // Accents — steel blue neumorphic
    static let inkAccent    = NSColor(red: 0.282, green: 0.455, blue: 0.690, alpha: 1) // #4874B0 steel blue
    static let inkActiveBg  = NSColor(red: 0.282, green: 0.455, blue: 0.690, alpha: 0.15) // active bg tint

    // Neumorphic depth
    static let inkRaised    = NSColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 1)   // #474749 raised surface
    static let inkInset     = NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)   // #1A1A1C recessed groove
}
