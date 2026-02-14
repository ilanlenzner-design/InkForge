import AppKit

enum ToolPalettePosition: String, CaseIterable {
    case left, right, top, bottom
}

protocol ToolPaletteDelegate: AnyObject {
    func toolPaletteDidSelectTool(_ toolName: String)
}

class ToolPaletteView: NSView {

    weak var delegate: ToolPaletteDelegate?

    private var toolButtons: [NSButton] = []
    private let toolDefs: [(name: String, key: String, symbol: String)] = [
        ("Pen",         "b", "pencil.tip"),
        ("Calligraphy", "c", "scribble"),
        ("Airbrush",    "a", "aqi.medium"),
        ("Smudge",      "s", "hand.point.up.left"),
        ("Fill",        "g", "drop.fill"),
        ("Eraser",      "e", "eraser"),
        ("Pan",         "h", "hand.raised"),
        ("Zoom",        "z", "magnifyingglass"),
        ("Eyedropper",  "i", "eyedropper"),
    ]

    private let buttonSize: CGFloat = 56
    private var stack: NSStackView?

    var position: ToolPalettePosition = .left {
        didSet { rebuildLayout() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        buildLayout()
    }

    private func rebuildLayout() {
        subviews.forEach { $0.removeFromSuperview() }
        toolButtons.removeAll()
        stack = nil
        buildLayout()
        // Restore active tool highlight
    }

    private func buildLayout() {
        let s = NSStackView()
        let isHorizontal = (position == .top || position == .bottom)
        s.orientation = isHorizontal ? .horizontal : .vertical
        s.spacing = 4
        s.alignment = isHorizontal ? .centerY : .centerX
        s.translatesAutoresizingMaskIntoConstraints = false
        addSubview(s)
        stack = s

        if isHorizontal {
            NSLayoutConstraint.activate([
                s.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                s.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                s.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                s.centerXAnchor.constraint(equalTo: centerXAnchor),
            ])
        }

        for (i, (name, key, symbolName)) in toolDefs.enumerated() {
            let btn = NSButton(frame: .zero)
            btn.bezelStyle = .toolbar
            btn.setButtonType(.toggle)
            btn.isBordered = true
            btn.tag = i
            btn.target = self
            btn.action = #selector(toolClicked(_:))
            btn.toolTip = "\(name) (\(key))"
            btn.refusesFirstResponder = true
            btn.translatesAutoresizingMaskIntoConstraints = false

            if name == "Fill" {
                btn.image = Self.makePaintBucketImage()
                btn.imagePosition = .imageOnly
            } else if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: name) {
                let config = NSImage.SymbolConfiguration(pointSize: 26, weight: .medium)
                btn.image = img.withSymbolConfiguration(config) ?? img
                btn.imagePosition = .imageOnly
            } else {
                btn.title = String(name.prefix(3))
            }

            btn.widthAnchor.constraint(equalToConstant: buttonSize).isActive = true
            btn.heightAnchor.constraint(equalToConstant: buttonSize).isActive = true

            toolButtons.append(btn)
            s.addArrangedSubview(btn)
        }

        // Default: Pen selected
        if !toolButtons.isEmpty {
            toolButtons[0].state = .on
        }
    }

    @objc private func toolClicked(_ sender: NSButton) {
        let name = toolDefs[sender.tag].name
        for btn in toolButtons { btn.state = .off }
        sender.state = .on
        delegate?.toolPaletteDidSelectTool(name)
    }

    func updateActiveTool(_ name: String) {
        for (i, btn) in toolButtons.enumerated() {
            btn.state = toolDefs[i].name == name ? .on : .off
        }
    }

    /// The fixed dimension size (width when vertical, height when horizontal)
    var paletteThickness: CGFloat { buttonSize + 12 }

    /// Draw a paint bucket icon programmatically (SF Symbols has no paint bucket)
    private static func makePaintBucketImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 28, height: 28))
        image.lockFocus()

        NSColor.labelColor.setFill()
        NSColor.labelColor.setStroke()

        // Bucket body (trapezoid)
        let body = NSBezierPath()
        body.move(to: NSPoint(x: 4, y: 19))
        body.line(to: NSPoint(x: 18, y: 19))
        body.line(to: NSPoint(x: 16, y: 5))
        body.line(to: NSPoint(x: 6, y: 5))
        body.close()
        body.fill()

        // Rim line at top
        let rim = NSBezierPath()
        rim.move(to: NSPoint(x: 3, y: 19.5))
        rim.line(to: NSPoint(x: 19, y: 19.5))
        rim.lineWidth = 2.5
        rim.lineCapStyle = .round
        rim.stroke()

        // Handle (arc above bucket)
        let handle = NSBezierPath()
        handle.appendArc(withCenter: NSPoint(x: 11, y: 19.5),
                         radius: 5,
                         startAngle: 0,
                         endAngle: 180)
        handle.lineWidth = 2.0
        handle.lineCapStyle = .round
        handle.stroke()

        // Paint drop (teardrop to the right of bucket)
        let drop = NSBezierPath()
        drop.move(to: NSPoint(x: 20, y: 17))
        drop.curve(to: NSPoint(x: 24, y: 8),
                   controlPoint1: NSPoint(x: 26, y: 16),
                   controlPoint2: NSPoint(x: 26, y: 9))
        drop.curve(to: NSPoint(x: 20, y: 13),
                   controlPoint1: NSPoint(x: 23, y: 6),
                   controlPoint2: NSPoint(x: 20, y: 9))
        drop.close()
        drop.fill()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
