import AppKit

protocol BrushPickerDelegate: AnyObject {
    func brushPickerDidSelectPreset(_ preset: BrushPreset)
}

class BrushPickerPopover: NSPopover {

    weak var pickerDelegate: BrushPickerDelegate?

    var selectedPresetName: String = "Round" {
        didSet { updateSelection() }
    }

    private var cells: [BrushPickerCell] = []

    private static let presets: [(name: String, preset: BrushPreset, key: String)] = [
        ("Round",        .defaultRound,        "B"),
        ("Pencil",       .defaultPencil,       "P"),
        ("Calligraphy",  .defaultCalligraphy,  "C"),
        ("Airbrush",     .defaultAirbrush,     "A"),
        ("Spray",        .defaultSpray,        "N"),
        ("Marker",       .defaultMarker,       "K"),
        ("Soft Round",   .defaultSoftRound,    "D"),
        ("Dry Brush",    .defaultDryBrush,     "F"),
        ("Charcoal",     .defaultCharcoal,     "R"),
        ("Ink",          .defaultInkSplatter,  "J"),
        ("Grunge",       .defaultGrunge,       ""),
        ("Flat Bristle", .defaultFlatBristle,  ""),
        ("Crosshatch",   .defaultCrosshatch,   ""),
    ]

    override init() {
        super.init()
        setupContent()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupContent()
    }

    private func setupContent() {
        let cellW: CGFloat = 104
        let cellH: CGFloat = 68
        let cols = 2
        let spacing: CGFloat = 4
        let padding: CGFloat = 10
        let rows = (Self.presets.count + cols - 1) / cols

        let gridW = CGFloat(cols) * cellW + CGFloat(cols - 1) * spacing
        let gridH = CGFloat(rows) * cellH + CGFloat(rows - 1) * spacing
        let containerW = gridW + padding * 2
        let containerH = gridH + padding * 2

        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerW, height: containerH))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.inkPanel.cgColor

        for (index, entry) in Self.presets.enumerated() {
            let row = index / cols
            let col = index % cols
            let x = padding + CGFloat(col) * (cellW + spacing)
            let y = padding + CGFloat(row) * (cellH + spacing)

            let cell = BrushPickerCell(
                frame: NSRect(x: x, y: y, width: cellW, height: cellH),
                brushName: entry.name,
                shortcutKey: entry.key,
                preset: entry.preset
            )
            cell.target = self
            cell.action = #selector(cellClicked(_:))
            cell.tag = index
            container.addSubview(cell)
            cells.append(cell)
        }

        let vc = NSViewController()
        vc.view = container
        contentViewController = vc
        behavior = .transient

        updateSelection()
    }

    @objc private func cellClicked(_ sender: BrushPickerCell) {
        let entry = Self.presets[sender.tag]
        selectedPresetName = entry.name
        pickerDelegate?.brushPickerDidSelectPreset(entry.preset)
    }

    private func updateSelection() {
        for (i, cell) in cells.enumerated() {
            cell.isSelected = Self.presets[i].name == selectedPresetName
        }
    }
}

// MARK: - Brush Picker Cell

class BrushPickerCell: NSControl {

    let brushName: String
    let shortcutKey: String
    var isSelected: Bool = false { didSet { needsDisplay = true } }

    private var previewImage: CGImage?

    init(frame: NSRect, brushName: String, shortcutKey: String, preset: BrushPreset) {
        self.brushName = brushName
        self.shortcutKey = shortcutKey
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        previewImage = Self.generatePreview(for: preset, width: Int(frame.width - 8), height: 38)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Background
        let bgColor = isSelected ? NSColor.inkActiveBg : NSColor.inkBtnBg
        ctx.setFillColor(bgColor.cgColor)
        let bgPath = CGPath(roundedRect: bounds, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.addPath(bgPath)
        ctx.fillPath()

        // Border
        if isSelected {
            ctx.setStrokeColor(NSColor.inkAccent.cgColor)
            ctx.setLineWidth(1.5)
        } else {
            ctx.setStrokeColor(NSColor.inkBorder.cgColor)
            ctx.setLineWidth(0.5)
        }
        ctx.addPath(bgPath)
        ctx.strokePath()

        // Preview image (top area)
        if let img = previewImage {
            let previewRect = CGRect(x: 4, y: 4, width: bounds.width - 8, height: 38)
            // Draw dark preview background
            ctx.setFillColor(NSColor.inkInset.cgColor)
            ctx.fill(previewRect)
            // Draw preview stroke (flip for CGImage in flipped view)
            ctx.saveGState()
            ctx.translateBy(x: previewRect.minX, y: previewRect.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: previewRect.width, height: previewRect.height))
            ctx.restoreGState()
        }

        // Label text
        let labelColor = isSelected ? NSColor.inkAccent : NSColor.inkTextDim
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: isSelected ? .semibold : .regular),
            .foregroundColor: labelColor,
        ]
        let displayName = shortcutKey.isEmpty ? brushName : "\(brushName)  \(shortcutKey)"
        let str = NSAttributedString(string: displayName, attributes: attrs)
        let sz = str.size()
        str.draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: 44))
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    // MARK: - Preview Generation

    private static func generatePreview(for preset: BrushPreset, width: Int, height: Int) -> CGImage? {
        let w = width
        let h = height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Dark background
        ctx.setFillColor(NSColor.inkInset.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Create a scaled preset for the preview
        var previewPreset = preset
        previewPreset.maxRadius = max(min(preset.maxRadius, 8), 3)
        previewPreset.minRadiusFraction = preset.minRadiusFraction

        // Generate S-curve stroke points
        let stroke = StrokeData(brushPreset: previewPreset, color: .white, layerIndex: 0)
        let numPoints = 24
        let padX: CGFloat = 8
        let midY = CGFloat(h) / 2
        let amplitude: CGFloat = CGFloat(h) * 0.28

        for i in 0..<numPoints {
            let t = CGFloat(i) / CGFloat(numPoints - 1)
            let x = padX + t * (CGFloat(w) - padX * 2)
            let y = midY + sin(t * .pi * 2) * amplitude
            // Pressure: light at edges, heavy in middle
            let pressure = 0.25 + 0.75 * sin(t * .pi)

            stroke.addPoint(StrokePoint(
                location: CGPoint(x: x, y: y),
                pressure: pressure,
                tiltX: 0, tiltY: 0,
                rotation: 0, timestamp: TimeInterval(i) * 0.01
            ))
        }

        let renderer = StrokeRenderer()
        renderer.renderStroke(stroke, into: ctx, preview: false)

        return ctx.makeImage()
    }
}
