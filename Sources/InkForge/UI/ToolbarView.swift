import AppKit

protocol ToolbarViewDelegate: AnyObject {
    func toolbarDidSelectTool(_ toolName: String)
    func toolbarDidRequestBrushSettings(relativeTo view: NSView)
    func toolbarDidRequestBrushPicker(relativeTo view: NSView)
    func toolbarDidRequestColorPicker(relativeTo view: NSView)
    func toolbarDidToggleLayerPanel()
    func toolbarDidUndo()
    func toolbarDidRedo()
    func toolbarDidRequestNewCanvas()
    func toolbarDidRequestExport(format: String)
    func toolbarDidRequestImportImage()
    func toolbarDidRequestOpenImageAsCanvas()
    func toolbarDidChangeZoom(_ percentage: Int)
    func toolbarDidRequestFitToScreen()
    func toolbarDidRequestAI()
}

class ToolbarView: NSView {

    weak var delegate: ToolbarViewDelegate?

    private var toolButtons: [NSButton] = []
    private var activeToolIndex: Int = 0
    private let toolDefs: [(name: String, symbol: String)] = [
        ("Pen",        "pencil.tip"),
        ("Pencil",     "pencil"),
        ("Marker",     "highlighter"),
        ("Spray",      "sparkles"),
        ("Soft Round", "circle.fill"),
        ("Smudge",     "hand.point.up.left"),
        ("Eraser",     "eraser"),
        ("Fill",       "paintbucket"),
        ("Eyedropper", "eyedropper"),
        ("Text",       "textformat"),
        ("Select",     "rectangle.dashed"),
        ("Transform",  "arrow.up.left.and.arrow.down.right"),
        ("Pan",        "hand.raised"),
        ("Zoom",       "magnifyingglass"),
    ]

    private var layerToggle: NSButton!
    private var colorCircle: ColorCircleView!
    private var brushSettingsBtn: NSButton!
    private var brushPickerBtn: NSButton!
    private var zoomSlider: NSSlider!
    private var zoomLabel: NSTextField!

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
        layer?.backgroundColor = NSColor.inkPanel.cgColor

        // Bottom border
        let border = CALayer()
        border.backgroundColor = NSColor.inkBorder.cgColor
        border.frame = CGRect(x: 0, y: 0, width: 10000, height: 1)
        border.autoresizingMask = [.layerWidthSizable]
        layer?.addSublayer(border)

        // -- Left stack: Actions, Undo, Redo, BrushSettings --
        let leftStack = NSStackView()
        leftStack.orientation = .horizontal
        leftStack.spacing = 8
        leftStack.alignment = .centerY
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leftStack)

        let actionsBtn = makeActionsButton()
        leftStack.addArrangedSubview(actionsBtn)

        let undoBtn = makeIconButton(symbol: "arrow.uturn.backward",
                                      action: #selector(undoClicked), tooltip: "Undo (⌘Z)")
        leftStack.addArrangedSubview(undoBtn)

        let redoBtn = makeIconButton(symbol: "arrow.uturn.forward",
                                      action: #selector(redoClicked), tooltip: "Redo (⇧⌘Z)")
        leftStack.addArrangedSubview(redoBtn)

        addSep(to: leftStack)

        brushSettingsBtn = makeIconButton(symbol: "slider.horizontal.3",
                                           action: #selector(brushSettingsClicked),
                                           tooltip: "Brush Settings")
        leftStack.addArrangedSubview(brushSettingsBtn)

        brushPickerBtn = makeIconButton(symbol: "paintbrush",
                                         action: #selector(brushPickerClicked),
                                         tooltip: "Brush Picker")
        leftStack.addArrangedSubview(brushPickerBtn)

        addSep(to: leftStack)

        let aiBtn = makeIconButton(symbol: "wand.and.stars",
                                    action: #selector(aiClicked),
                                    tooltip: "AI Edit (⇧⌘A)")
        leftStack.addArrangedSubview(aiBtn)

        // -- Right stack: Tool toggles, Layers, Color --
        let rightStack = NSStackView()
        rightStack.orientation = .horizontal
        rightStack.spacing = 6
        rightStack.alignment = .centerY
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rightStack)

        for (i, (name, symbolName)) in toolDefs.enumerated() {
            // Separators between tool groups
            // Brushes: 0-4 | Effects: 5-7 | Utility: 8-9 | Selection: 10-11 | Navigation: 12-13
            if i == 5 || i == 8 || i == 10 || i == 12 { addSep(to: rightStack) }

            let btn = NSButton(frame: .zero)
            btn.bezelStyle = .toolbar
            btn.setButtonType(.momentaryPushIn)
            btn.isBordered = false
            btn.tag = i
            btn.target = self
            btn.action = #selector(toolClicked(_:))
            btn.refusesFirstResponder = true
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 8

            if name == "Fill" {
                btn.image = Self.makePaintBucketImage()
                btn.imagePosition = .imageOnly
                btn.toolTip = "Fill (G)"
                btn.contentTintColor = .inkText
            } else if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: name) {
                let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
                btn.image = img.withSymbolConfiguration(config) ?? img
                btn.imagePosition = .imageOnly
                btn.contentTintColor = .inkText
                let key: String
                switch name {
                case "Pen":        key = "B"
                case "Pencil":     key = "P"
                case "Marker":     key = "K"
                case "Spray":      key = "N"
                case "Soft Round": key = "D"
                case "Smudge":     key = "S"
                case "Eraser":     key = "E"
                case "Eyedropper": key = "I"
                case "Text":       key = "T"
                case "Select":     key = "M"
                case "Transform":  key = "V"
                case "Pan":        key = "H"
                case "Zoom":       key = "Z"
                default:           key = ""
                }
                btn.toolTip = "\(name) (\(key))"
            }

            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(equalToConstant: 40),
                btn.heightAnchor.constraint(equalToConstant: 40),
            ])

            toolButtons.append(btn)
            rightStack.addArrangedSubview(btn)
        }
        activeToolIndex = 0
        updateToolButtonStyles()

        addSep(to: rightStack)

        layerToggle = makeIconButton(symbol: "square.3.layers.3d",
                                      action: #selector(layerToggleClicked),
                                      tooltip: "Layers (L)")
        rightStack.addArrangedSubview(layerToggle)

        // Color circle
        colorCircle = ColorCircleView(color: .black)
        colorCircle.translatesAutoresizingMaskIntoConstraints = false
        colorCircle.target = self
        colorCircle.action = #selector(colorClicked)
        NSLayoutConstraint.activate([
            colorCircle.widthAnchor.constraint(equalToConstant: 36),
            colorCircle.heightAnchor.constraint(equalToConstant: 36),
        ])
        rightStack.addArrangedSubview(colorCircle)

        // -- Zoom slider in left stack --
        addSep(to: leftStack)

        zoomSlider = NSSlider(value: 100, minValue: 5, maxValue: 3200,
                               target: self, action: #selector(zoomSliderChanged))
        zoomSlider.translatesAutoresizingMaskIntoConstraints = false
        zoomSlider.widthAnchor.constraint(equalToConstant: 100).isActive = true
        leftStack.addArrangedSubview(zoomSlider)

        zoomLabel = NSTextField(labelWithString: "100%")
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomLabel.textColor = .inkText
        zoomLabel.translatesAutoresizingMaskIntoConstraints = false
        zoomLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        leftStack.addArrangedSubview(zoomLabel)

        // Layout left/right stacks
        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // MARK: - Tool Button Styling

    private func updateToolButtonStyles() {
        for (i, btn) in toolButtons.enumerated() {
            if i == activeToolIndex {
                // Active: inset feel with accent glow border
                btn.layer?.backgroundColor = NSColor.inkActiveBg.cgColor
                btn.layer?.borderWidth = 1.5
                btn.layer?.borderColor = NSColor.inkAccent.cgColor
                btn.layer?.shadowColor = NSColor.inkAccent.withAlphaComponent(0.35).cgColor
                btn.layer?.shadowOffset = .zero
                btn.layer?.shadowRadius = 6
                btn.layer?.shadowOpacity = 1
                btn.contentTintColor = .inkAccent
            } else {
                // Inactive: raised neumorphic
                btn.layer?.backgroundColor = NSColor.inkBtnBg.cgColor
                btn.layer?.borderWidth = 0.5
                btn.layer?.borderColor = NSColor(white: 0.35, alpha: 1).cgColor
                btn.layer?.shadowColor = NSColor.black.withAlphaComponent(0.35).cgColor
                btn.layer?.shadowOffset = CGSize(width: 1, height: -1)
                btn.layer?.shadowRadius = 3
                btn.layer?.shadowOpacity = 1
                btn.contentTintColor = .inkText
            }
        }
    }

    // MARK: - Factory

    private func makeIconButton(symbol: String, action: Selector, tooltip: String) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .toolbar
        btn.setButtonType(.momentaryPushIn)
        btn.isBordered = false
        btn.refusesFirstResponder = true
        btn.toolTip = tooltip
        btn.target = self
        btn.action = action
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 8
        btn.layer?.backgroundColor = NSColor.inkBtnBg.cgColor
        btn.layer?.borderWidth = 0.5
        btn.layer?.borderColor = NSColor(white: 0.35, alpha: 1).cgColor
        btn.layer?.shadowColor = NSColor.black.withAlphaComponent(0.35).cgColor
        btn.layer?.shadowOffset = CGSize(width: 1, height: -1)
        btn.layer?.shadowRadius = 3
        btn.layer?.shadowOpacity = 1

        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) {
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            btn.image = img.withSymbolConfiguration(config) ?? img
            btn.imagePosition = .imageOnly
            btn.contentTintColor = .inkText
        } else {
            btn.title = String(tooltip.prefix(3))
        }

        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 36),
            btn.heightAnchor.constraint(equalToConstant: 36),
        ])
        return btn
    }

    private func makeActionsButton() -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .toolbar
        btn.setButtonType(.momentaryPushIn)
        btn.isBordered = false
        btn.refusesFirstResponder = true
        btn.toolTip = "Actions"
        btn.target = self
        btn.action = #selector(actionsClicked(_:))
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 8
        btn.layer?.backgroundColor = NSColor.inkBtnBg.cgColor
        btn.layer?.borderWidth = 0.5
        btn.layer?.borderColor = NSColor(white: 0.35, alpha: 1).cgColor
        btn.layer?.shadowColor = NSColor.black.withAlphaComponent(0.35).cgColor
        btn.layer?.shadowOffset = CGSize(width: 1, height: -1)
        btn.layer?.shadowRadius = 3
        btn.layer?.shadowOpacity = 1

        if let img = NSImage(systemSymbolName: "wrench", accessibilityDescription: "Actions") {
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            btn.image = img.withSymbolConfiguration(config) ?? img
            btn.imagePosition = .imageOnly
            btn.contentTintColor = .inkText
        } else {
            btn.title = "Act"
        }

        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 36),
            btn.heightAnchor.constraint(equalToConstant: 36),
        ])
        return btn
    }

    private func addSep(to stack: NSStackView) {
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.inkBorder.cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sep.widthAnchor.constraint(equalToConstant: 1),
            sep.heightAnchor.constraint(equalToConstant: 36),
        ])
        stack.addArrangedSubview(sep)
    }

    // MARK: - Actions

    @objc private func actionsClicked(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Canvas...", action: #selector(newCanvasAction), keyEquivalent: "")
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Export as PNG...", action: #selector(exportPNG), keyEquivalent: "")
        menu.items.last?.target = self
        menu.addItem(withTitle: "Export as JPEG...", action: #selector(exportJPEG), keyEquivalent: "")
        menu.items.last?.target = self
        menu.addItem(withTitle: "Export as TIFF...", action: #selector(exportTIFF), keyEquivalent: "")
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Image as Canvas...", action: #selector(openImageAsCanvasAction), keyEquivalent: "")
        menu.items.last?.target = self
        menu.addItem(withTitle: "Import Image as Layer...", action: #selector(importAction), keyEquivalent: "")
        menu.items.last?.target = self

        let point = NSPoint(x: 0, y: sender.bounds.maxY + 4)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc private func newCanvasAction() { delegate?.toolbarDidRequestNewCanvas() }
    @objc private func exportPNG()       { delegate?.toolbarDidRequestExport(format: "png") }
    @objc private func exportJPEG()      { delegate?.toolbarDidRequestExport(format: "jpeg") }
    @objc private func exportTIFF()      { delegate?.toolbarDidRequestExport(format: "tiff") }
    @objc private func openImageAsCanvasAction() { delegate?.toolbarDidRequestOpenImageAsCanvas() }
    @objc private func importAction()    { delegate?.toolbarDidRequestImportImage() }

    @objc private func undoClicked()     { delegate?.toolbarDidUndo() }
    @objc private func redoClicked()     { delegate?.toolbarDidRedo() }

    @objc private func brushSettingsClicked() {
        delegate?.toolbarDidRequestBrushSettings(relativeTo: brushSettingsBtn)
    }

    @objc private func brushPickerClicked() {
        delegate?.toolbarDidRequestBrushPicker(relativeTo: brushPickerBtn)
    }

    @objc private func aiClicked() {
        delegate?.toolbarDidRequestAI()
    }

    @objc private func zoomSliderChanged() {
        let percentage = Int(zoomSlider.doubleValue)
        zoomLabel.stringValue = "\(percentage)%"
        delegate?.toolbarDidChangeZoom(percentage)
    }

    @objc private func toolClicked(_ sender: NSButton) {
        let name = toolDefs[sender.tag].name

        // Double-click Pan → fit to screen
        if name == "Pan" && activeToolIndex == sender.tag {
            delegate?.toolbarDidRequestFitToScreen()
            return
        }

        // Toggle Select/Transform: clicking again switches back to Pen
        if activeToolIndex == sender.tag && (name == "Select" || name == "Transform") {
            activeToolIndex = 0  // Pen
            updateToolButtonStyles()
            delegate?.toolbarDidSelectTool(toolDefs[0].name)
            return
        }

        activeToolIndex = sender.tag
        updateToolButtonStyles()
        delegate?.toolbarDidSelectTool(name)
    }

    @objc private func layerToggleClicked() {
        delegate?.toolbarDidToggleLayerPanel()
    }

    @objc private func colorClicked() {
        delegate?.toolbarDidRequestColorPicker(relativeTo: colorCircle)
    }

    // MARK: - Updates from controller

    func updateActiveTool(_ name: String) {
        let mappedName: String
        switch name {
        case "Pen", "Round", "Calligraphy", "Airbrush": mappedName = "Pen"
        case "Selection": mappedName = "Select"
        default: mappedName = name
        }
        for (i, _) in toolDefs.enumerated() {
            if toolDefs[i].name == mappedName {
                activeToolIndex = i
                break
            }
        }
        updateToolButtonStyles()
    }

    func updateColor(_ color: NSColor) {
        colorCircle?.color = color
    }

    func updateBrushSize(_ size: CGFloat) {}

    func updateZoom(_ percent: Int) {
        zoomSlider?.doubleValue = Double(percent)
        zoomLabel?.stringValue = "\(percent)%"
    }

    // MARK: - Paint Bucket Icon

    private static func makePaintBucketImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus()

        NSColor.labelColor.setFill()
        NSColor.labelColor.setStroke()

        let body = NSBezierPath()
        body.move(to: NSPoint(x: 3, y: 14))
        body.line(to: NSPoint(x: 13, y: 14))
        body.line(to: NSPoint(x: 12, y: 4))
        body.line(to: NSPoint(x: 4, y: 4))
        body.close()
        body.fill()

        let rim = NSBezierPath()
        rim.move(to: NSPoint(x: 2, y: 14.5))
        rim.line(to: NSPoint(x: 14, y: 14.5))
        rim.lineWidth = 2
        rim.lineCapStyle = .round
        rim.stroke()

        let handle = NSBezierPath()
        handle.appendArc(withCenter: NSPoint(x: 8, y: 14.5),
                         radius: 4, startAngle: 0, endAngle: 180)
        handle.lineWidth = 1.5
        handle.lineCapStyle = .round
        handle.stroke()

        let drop = NSBezierPath()
        drop.move(to: NSPoint(x: 15, y: 13))
        drop.curve(to: NSPoint(x: 18, y: 6),
                   controlPoint1: NSPoint(x: 19, y: 12),
                   controlPoint2: NSPoint(x: 19, y: 7))
        drop.curve(to: NSPoint(x: 15, y: 10),
                   controlPoint1: NSPoint(x: 17, y: 4),
                   controlPoint2: NSPoint(x: 15, y: 7))
        drop.close()
        drop.fill()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

// MARK: - Color Circle View

class ColorCircleView: NSControl {

    var color: NSColor = .black {
        didSet { needsDisplay = true }
    }

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 36, height: 36)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let inset: CGFloat = 3
        let rect = bounds.insetBy(dx: inset, dy: inset)

        // Drop shadow behind circle
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 1, height: -1), blur: 3,
                       color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setFillColor(NSColor.inkBtnBg.cgColor)
        ctx.fillEllipse(in: rect)
        ctx.restoreGState()

        // Outer ring
        ctx.setStrokeColor(NSColor(white: 0.35, alpha: 1).cgColor)
        ctx.setLineWidth(1.5)
        ctx.addEllipse(in: rect)
        ctx.strokePath()

        // Filled circle
        let innerRect = rect.insetBy(dx: 3, dy: 3)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: innerRect)

        // Inner accent ring
        ctx.setStrokeColor(NSColor.inkAccent.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(1.0)
        ctx.addEllipse(in: innerRect.insetBy(dx: -0.5, dy: -0.5))
        ctx.strokePath()
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }
}
