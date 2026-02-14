import AppKit

// MARK: - Delegate Protocol

protocol ColorPickerPopoverDelegate: AnyObject {
    func colorPickerDidSelectColor(_ color: NSColor)
}

// MARK: - ColorPickerPopover

class ColorPickerPopover: NSPopover {

    weak var pickerDelegate: ColorPickerPopoverDelegate?

    private var colorWheel: ColorWheelView!
    private var hueSlider: NSSlider!
    private var satSlider: NSSlider!
    private var briSlider: NSSlider!
    private var hexField: NSTextField!
    private var previewView: NSView!
    private var historyStack: NSStackView!

    private(set) var selectedColor: NSColor = .white {
        didSet { syncUI() }
    }

    private static var colorHistory: [NSColor] = []

    override init() {
        super.init()
        setupContent()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupContent()
    }

    // MARK: - Public API

    func setColor(_ color: NSColor) {
        selectedColor = color
        colorWheel.setColor(color)
    }

    func addToHistory(_ color: NSColor) {
        // Avoid duplicates at the front
        Self.colorHistory.removeAll { $0 == color }
        Self.colorHistory.insert(color, at: 0)
        if Self.colorHistory.count > 10 {
            Self.colorHistory = Array(Self.colorHistory.prefix(10))
        }
        rebuildHistory()
    }

    // MARK: - Setup

    private func setupContent() {
        let width: CGFloat = 240
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 400))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])

        // Color wheel
        colorWheel = ColorWheelView(frame: NSRect(x: 0, y: 0, width: 180, height: 180))
        colorWheel.translatesAutoresizingMaskIntoConstraints = false
        colorWheel.onColorChange = { [weak self] color in
            guard let self else { return }
            self.selectedColor = color
            self.pickerDelegate?.colorPickerDidSelectColor(color)
        }
        NSLayoutConstraint.activate([
            colorWheel.widthAnchor.constraint(equalToConstant: 180),
            colorWheel.heightAnchor.constraint(equalToConstant: 180),
        ])
        stack.addArrangedSubview(colorWheel)

        // HSB Sliders
        hueSlider = makeSliderRow(label: "H", min: 0, max: 360, value: 0, stack: stack)
        satSlider = makeSliderRow(label: "S", min: 0, max: 100, value: 0, stack: stack)
        briSlider = makeSliderRow(label: "B", min: 0, max: 100, value: 100, stack: stack)

        // Hex input row
        let hexRow = NSStackView()
        hexRow.orientation = .horizontal
        hexRow.spacing = 6
        hexRow.translatesAutoresizingMaskIntoConstraints = false

        let hexLabel = NSTextField(labelWithString: "#")
        hexLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        hexRow.addArrangedSubview(hexLabel)

        hexField = NSTextField(string: "FFFFFF")
        hexField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        hexField.alignment = .center
        hexField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        hexField.delegate = self
        hexRow.addArrangedSubview(hexField)

        // Preview swatch
        previewView = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 20))
        previewView.wantsLayer = true
        previewView.layer?.backgroundColor = NSColor.white.cgColor
        previewView.layer?.cornerRadius = 3
        previewView.layer?.borderWidth = 1
        previewView.layer?.borderColor = NSColor.separatorColor.cgColor
        NSLayoutConstraint.activate([
            previewView.widthAnchor.constraint(equalToConstant: 28),
            previewView.heightAnchor.constraint(equalToConstant: 20),
        ])
        hexRow.addArrangedSubview(previewView)

        hexRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.addArrangedSubview(hexRow)

        // Color history
        let historyLabel = NSTextField(labelWithString: "Recent")
        historyLabel.font = .systemFont(ofSize: 10, weight: .medium)
        historyLabel.textColor = .secondaryLabelColor
        historyLabel.alignment = .left
        historyLabel.translatesAutoresizingMaskIntoConstraints = false
        historyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.addArrangedSubview(historyLabel)

        historyStack = NSStackView()
        historyStack.orientation = .horizontal
        historyStack.spacing = 4
        historyStack.alignment = .centerY
        historyStack.translatesAutoresizingMaskIntoConstraints = false
        historyStack.heightAnchor.constraint(equalToConstant: 20).isActive = true
        historyStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.addArrangedSubview(historyStack)

        rebuildHistory()

        let vc = NSViewController()
        vc.view = container
        contentViewController = vc
        behavior = .transient
    }

    private func makeSliderRow(label: String, min: Double, max: Double,
                                value: Double, stack: NSStackView) -> NSSlider {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false

        let lbl = NSTextField(labelWithString: label)
        lbl.font = .systemFont(ofSize: 11, weight: .medium)
        lbl.widthAnchor.constraint(equalToConstant: 16).isActive = true
        row.addArrangedSubview(lbl)

        let slider = NSSlider(value: value, minValue: min, maxValue: max,
                               target: self, action: #selector(sliderChanged))
        slider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        row.addArrangedSubview(slider)

        let valLabel = NSTextField(labelWithString: "\(Int(value))")
        valLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        valLabel.widthAnchor.constraint(equalToConstant: 30).isActive = true
        valLabel.alignment = .right
        valLabel.tag = 999 // marker to find value labels
        row.addArrangedSubview(valLabel)

        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.addArrangedSubview(row)
        return slider
    }

    // MARK: - Sync

    private func syncUI() {
        guard let hsb = selectedColor.usingColorSpace(.deviceRGB) else { return }
        let h = hsb.hueComponent
        let s = hsb.saturationComponent
        let b = hsb.brightnessComponent

        hueSlider?.doubleValue = Double(h) * 360
        satSlider?.doubleValue = Double(s) * 100
        briSlider?.doubleValue = Double(b) * 100

        updateValueLabel(for: hueSlider, value: Int(h * 360))
        updateValueLabel(for: satSlider, value: Int(s * 100))
        updateValueLabel(for: briSlider, value: Int(b * 100))

        hexField?.stringValue = hexString(from: selectedColor)
        previewView?.layer?.backgroundColor = selectedColor.cgColor
    }

    private func updateValueLabel(for slider: NSSlider?, value: Int) {
        guard let slider else { return }
        if let row = slider.superview as? NSStackView,
           let label = row.arrangedSubviews.first(where: { $0.tag == 999 }) as? NSTextField {
            label.stringValue = "\(value)"
        }
    }

    @objc private func sliderChanged() {
        let h = CGFloat(hueSlider.doubleValue / 360.0)
        let s = CGFloat(satSlider.doubleValue / 100.0)
        let b = CGFloat(briSlider.doubleValue / 100.0)
        let color = NSColor(hue: h, saturation: s, brightness: b, alpha: 1)
        selectedColor = color
        colorWheel.setColor(color)
        pickerDelegate?.colorPickerDidSelectColor(color)
    }

    // MARK: - Hex Helpers

    private func hexString(from color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return "000000" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }

    private func colorFromHex(_ hex: String) -> NSColor? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let val = UInt32(cleaned, radix: 16) else { return nil }
        let r = CGFloat((val >> 16) & 0xFF) / 255.0
        let g = CGFloat((val >> 8) & 0xFF) / 255.0
        let b = CGFloat(val & 0xFF) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: 1)
    }

    // MARK: - History

    private func rebuildHistory() {
        guard let historyStack else { return }
        historyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (index, color) in Self.colorHistory.prefix(10).enumerated() {
            let swatch = HistorySwatchView(color: color, index: index)
            swatch.onTap = { [weak self] c in
                guard let self else { return }
                self.selectedColor = c
                self.colorWheel.setColor(c)
                self.pickerDelegate?.colorPickerDidSelectColor(c)
            }
            NSLayoutConstraint.activate([
                swatch.widthAnchor.constraint(equalToConstant: 18),
                swatch.heightAnchor.constraint(equalToConstant: 18),
            ])
            historyStack.addArrangedSubview(swatch)
        }
    }

    @objc private func historySwatchClicked(_ sender: NSView) {
        let idx = sender.tag
        guard idx < Self.colorHistory.count else { return }
        let color = Self.colorHistory[idx]
        selectedColor = color
        colorWheel.setColor(color)
        pickerDelegate?.colorPickerDidSelectColor(color)
    }
}

// MARK: - NSTextFieldDelegate (hex input)

extension ColorPickerPopover: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === hexField else { return }
        if let color = colorFromHex(field.stringValue) {
            selectedColor = color
            colorWheel.setColor(color)
            pickerDelegate?.colorPickerDidSelectColor(color)
        } else {
            // Revert to current
            field.stringValue = hexString(from: selectedColor)
        }
    }
}

// MARK: - HistorySwatchView

private class HistorySwatchView: NSView {
    var onTap: ((NSColor) -> Void)?
    private let swatchColor: NSColor

    init(color: NSColor, index: Int) {
        self.swatchColor = color
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        self.layer?.backgroundColor = color.cgColor
        self.layer?.cornerRadius = 3
        self.layer?.borderWidth = 0.5
        self.layer?.borderColor = NSColor.separatorColor.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        onTap?(swatchColor)
    }
}

// MARK: - ColorWheelView

class ColorWheelView: NSView {

    var onColorChange: ((NSColor) -> Void)?

    private var hue: CGFloat = 0
    private var saturation: CGFloat = 1
    private var brightness: CGFloat = 1

    private let ringWidth: CGFloat = 20
    private var squareBitmap: CGImage?
    private var lastSquareHue: CGFloat = -1

    override var isFlipped: Bool { false }

    func setColor(_ color: NSColor) {
        guard let c = color.usingColorSpace(.deviceRGB) else { return }
        hue = c.hueComponent
        saturation = c.saturationComponent
        brightness = c.brightnessComponent
        invalidateSquare()
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let size = min(bounds.width, bounds.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let outerRadius = size / 2
        let innerRadius = outerRadius - ringWidth

        // Draw hue ring
        drawHueRing(ctx: ctx, center: center, outerRadius: outerRadius,
                     innerRadius: innerRadius)

        // Draw SB square inside the ring
        let squareInset: CGFloat = 6
        let squareRadius = innerRadius - squareInset
        let squareSide = squareRadius * sqrt(2) // largest square that fits in circle
        let squareOrigin = CGPoint(x: center.x - squareSide / 2,
                                    y: center.y - squareSide / 2)
        let squareRect = CGRect(origin: squareOrigin,
                                 size: CGSize(width: squareSide, height: squareSide))

        drawSBSquare(ctx: ctx, rect: squareRect)

        // Draw indicator on hue ring
        drawHueIndicator(ctx: ctx, center: center, radius: innerRadius + ringWidth / 2)

        // Draw crosshair on SB square
        drawSBIndicator(ctx: ctx, rect: squareRect)
    }

    /// Angular offset to rotate the hue ring so red is at 12 o'clock (top)
    private static let ringOffset: CGFloat = .pi / 2

    private func drawHueRing(ctx: CGContext, center: CGPoint,
                              outerRadius: CGFloat, innerRadius: CGFloat) {
        let segments = 360
        for i in 0..<segments {
            let startAngle = CGFloat(i) * .pi / 180 + Self.ringOffset
            let endAngle = CGFloat(i + 1) * .pi / 180 + Self.ringOffset

            let path = CGMutablePath()
            path.addArc(center: center, radius: outerRadius,
                        startAngle: startAngle, endAngle: endAngle, clockwise: false)
            path.addArc(center: center, radius: innerRadius,
                        startAngle: endAngle, endAngle: startAngle, clockwise: true)
            path.closeSubpath()

            let segHue = CGFloat(i) / CGFloat(segments)
            ctx.setFillColor(NSColor(hue: segHue, saturation: 1, brightness: 1, alpha: 1).cgColor)
            ctx.addPath(path)
            ctx.fillPath()
        }
    }

    private func drawSBSquare(ctx: CGContext, rect: CGRect) {
        let image = sbBitmap(for: hue, width: Int(rect.width), height: Int(rect.height))
        ctx.draw(image, in: rect)
    }

    private func sbBitmap(for hue: CGFloat, width: Int, height: Int) -> CGImage {
        let w = max(width, 1)
        let h = max(height, 1)
        if let cached = squareBitmap, lastSquareHue == hue { return cached }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = w * 4
        var data = [UInt8](repeating: 255, count: h * bytesPerRow)

        for y in 0..<h {
            let bri = CGFloat(h - 1 - y) / CGFloat(h - 1) // row 0 = bright (top), row h-1 = dark (bottom)
            for x in 0..<w {
                let sat = CGFloat(x) / CGFloat(w - 1)
                let c = NSColor(hue: hue, saturation: sat, brightness: bri, alpha: 1)
                    .usingColorSpace(.deviceRGB)!
                let offset = (y * bytesPerRow) + (x * 4)
                data[offset]     = UInt8(c.redComponent * 255)
                data[offset + 1] = UInt8(c.greenComponent * 255)
                data[offset + 2] = UInt8(c.blueComponent * 255)
                data[offset + 3] = 255
            }
        }

        let provider = CGDataProvider(data: Data(data) as CFData)!
        let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: bytesPerRow, space: colorSpace,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil,
                            shouldInterpolate: true, intent: .defaultIntent)!
        squareBitmap = image
        lastSquareHue = hue
        return image
    }

    private func invalidateSquare() {
        lastSquareHue = -1
        squareBitmap = nil
    }

    private func drawHueIndicator(ctx: CGContext, center: CGPoint, radius: CGFloat) {
        let angle = hue * 2 * .pi + Self.ringOffset
        let x = center.x + radius * cos(angle)
        let y = center.y + radius * sin(angle)
        let r: CGFloat = 5
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: CGRect(x: x - r - 1, y: y - r - 1,
                                      width: (r + 1) * 2, height: (r + 1) * 2))
    }

    private func drawSBIndicator(ctx: CGContext, rect: CGRect) {
        let x = rect.origin.x + saturation * rect.width
        let y = rect.origin.y + brightness * rect.height
        let r: CGFloat = 5
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: CGRect(x: x - r - 1, y: y - r - 1,
                                      width: (r + 1) * 2, height: (r + 1) * 2))
    }

    // MARK: - Hit Testing & Mouse

    private enum DragTarget {
        case ring, square, none
    }
    private var dragTarget: DragTarget = .none

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragTarget = hitTarget(point)
        handleMouse(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        handleMouse(at: point)
    }

    override func mouseUp(with event: NSEvent) {
        dragTarget = .none
    }

    private func hitTarget(_ point: CGPoint) -> DragTarget {
        let size = min(bounds.width, bounds.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let outerRadius = size / 2
        let innerRadius = outerRadius - ringWidth

        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = sqrt(dx * dx + dy * dy)

        if dist >= innerRadius && dist <= outerRadius {
            return .ring
        }

        let squareInset: CGFloat = 6
        let squareRadius = innerRadius - squareInset
        let squareSide = squareRadius * sqrt(2)
        let squareRect = CGRect(x: center.x - squareSide / 2,
                                 y: center.y - squareSide / 2,
                                 width: squareSide, height: squareSide)
        if squareRect.contains(point) {
            return .square
        }

        return .none
    }

    private func handleMouse(at point: CGPoint) {
        let size = min(bounds.width, bounds.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let outerRadius = size / 2
        let innerRadius = outerRadius - ringWidth

        switch dragTarget {
        case .ring:
            let dx = point.x - center.x
            let dy = point.y - center.y
            var angle = atan2(dy, dx) - Self.ringOffset
            if angle < 0 { angle += 2 * .pi }
            if angle >= 2 * .pi { angle -= 2 * .pi }
            hue = angle / (2 * .pi)
            invalidateSquare()
            needsDisplay = true
            emitColor()

        case .square:
            let squareInset: CGFloat = 6
            let squareRadius = innerRadius - squareInset
            let squareSide = squareRadius * sqrt(2)
            let squareOrigin = CGPoint(x: center.x - squareSide / 2,
                                        y: center.y - squareSide / 2)
            let sx = (point.x - squareOrigin.x) / squareSide
            let sy = (point.y - squareOrigin.y) / squareSide
            saturation = min(max(sx, 0), 1)
            brightness = min(max(sy, 0), 1)
            needsDisplay = true
            emitColor()

        case .none:
            break
        }
    }

    private func emitColor() {
        let color = NSColor(hue: hue, saturation: saturation,
                             brightness: brightness, alpha: 1)
        onColorChange?(color)
    }
}
