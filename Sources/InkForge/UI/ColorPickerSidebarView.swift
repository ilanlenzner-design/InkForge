import AppKit

protocol ColorPickerSidebarDelegate: AnyObject {
    func colorPickerSidebarDidSelectColor(_ color: NSColor)
}

class ColorPickerSidebarView: NSView {

    weak var delegate: ColorPickerSidebarDelegate?

    private var colorWheel: ColorWheelView!
    private var hueSlider: NSSlider!
    private var satSlider: NSSlider!
    private var briSlider: NSSlider!
    private var hexField: NSTextField!
    private var historyStack: NSStackView!

    private(set) var selectedColor: NSColor = .black {
        didSet { syncUI() }
    }

    private static var colorHistory: [NSColor] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    // MARK: - Public

    func setColor(_ color: NSColor) {
        selectedColor = color
        colorWheel?.setColor(color)
    }

    func addToHistory(_ color: NSColor) {
        Self.colorHistory.removeAll { $0 == color }
        Self.colorHistory.insert(color, at: 0)
        if Self.colorHistory.count > 10 {
            Self.colorHistory = Array(Self.colorHistory.prefix(10))
        }
        rebuildHistory()
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.inkPanelAlt.cgColor

        // Top border
        let topBorder = CALayer()
        topBorder.backgroundColor = NSColor.inkBorder.cgColor
        topBorder.frame = CGRect(x: 0, y: 0, width: 10000, height: 1)
        topBorder.autoresizingMask = [.layerWidthSizable, .layerMaxYMargin]
        // Position at top (flipped in layout, so maxY)
        topBorder.autoresizingMask = [.layerWidthSizable]
        layer?.addSublayer(topBorder)
        // We'll position it in layout override

        // Left border
        let leftBorder = CALayer()
        leftBorder.backgroundColor = NSColor.inkBorder.cgColor
        leftBorder.frame = CGRect(x: 0, y: 0, width: 1, height: 10000)
        leftBorder.autoresizingMask = [.layerHeightSizable]
        layer?.addSublayer(leftBorder)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
        ])

        // Color wheel — square, width of stack
        colorWheel = ColorWheelView(frame: .zero)
        colorWheel.translatesAutoresizingMaskIntoConstraints = false
        colorWheel.onColorChange = { [weak self] color in
            guard let self else { return }
            self.selectedColor = color
            self.delegate?.colorPickerSidebarDidSelectColor(color)
        }
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
        hexLabel.textColor = .inkTextDim
        hexRow.addArrangedSubview(hexLabel)

        hexField = NSTextField(string: "000000")
        hexField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        hexField.alignment = .center
        hexField.textColor = .inkText
        hexField.backgroundColor = .inkPanel
        hexField.isBordered = true
        hexField.wantsLayer = true
        hexField.layer?.cornerRadius = 4
        hexField.layer?.borderWidth = 1
        hexField.layer?.borderColor = NSColor.inkBorder.cgColor
        hexField.delegate = self
        hexRow.addArrangedSubview(hexField)
        stack.addArrangedSubview(hexRow)

        // "RECENT" label
        let recentLabel = NSTextField(labelWithString: "RECENT")
        recentLabel.font = .systemFont(ofSize: 10, weight: .bold)
        recentLabel.textColor = .inkTextMuted
        recentLabel.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(recentLabel)

        // Recent colors
        historyStack = NSStackView()
        historyStack.orientation = .horizontal
        historyStack.spacing = 4
        historyStack.alignment = .centerY
        historyStack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(historyStack)

        // Now activate cross-view constraints (all views are in the hierarchy)
        NSLayoutConstraint.activate([
            colorWheel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            colorWheel.heightAnchor.constraint(equalTo: colorWheel.widthAnchor),
            hexField.widthAnchor.constraint(equalToConstant: 80),
            hexRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            historyStack.heightAnchor.constraint(equalToConstant: 20),
            historyStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    override func layout() {
        super.layout()
        // Position top border at actual top
        if let topBorder = layer?.sublayers?.first {
            topBorder.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        }
    }

    private func makeSliderRow(label: String, min: Double, max: Double,
                                value: Double, stack: NSStackView) -> NSSlider {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false

        let lbl = NSTextField(labelWithString: label)
        lbl.font = .systemFont(ofSize: 11, weight: .semibold)
        lbl.textColor = .inkTextDim
        row.addArrangedSubview(lbl)

        let slider = NSSlider(value: value, minValue: min, maxValue: max,
                               target: self, action: #selector(sliderChanged))
        row.addArrangedSubview(slider)

        let valLabel = NSTextField(labelWithString: "\(Int(value))")
        valLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valLabel.textColor = .inkText
        valLabel.alignment = .right
        valLabel.tag = 999
        row.addArrangedSubview(valLabel)

        // Add to stack first, then set cross-view constraints
        stack.addArrangedSubview(row)
        NSLayoutConstraint.activate([
            lbl.widthAnchor.constraint(equalToConstant: 16),
            valLabel.widthAnchor.constraint(equalToConstant: 30),
            row.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return slider
    }

    // MARK: - Actions

    @objc private func sliderChanged() {
        let h = CGFloat(hueSlider.doubleValue / 360.0)
        let s = CGFloat(satSlider.doubleValue / 100.0)
        let b = CGFloat(briSlider.doubleValue / 100.0)
        let color = NSColor(hue: h, saturation: s, brightness: b, alpha: 1)
        selectedColor = color
        colorWheel.setColor(color)
        delegate?.colorPickerSidebarDidSelectColor(color)
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
    }

    private func updateValueLabel(for slider: NSSlider?, value: Int) {
        guard let slider else { return }
        if let row = slider.superview as? NSStackView,
           let label = row.arrangedSubviews.first(where: { $0.tag == 999 }) as? NSTextField {
            label.stringValue = "\(value)"
        }
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

        for color in Self.colorHistory.prefix(10) {
            let swatch = ClickableSwatch(color: color)
            swatch.onTap = { [weak self] c in
                guard let self else { return }
                self.selectedColor = c
                self.colorWheel.setColor(c)
                self.delegate?.colorPickerSidebarDidSelectColor(c)
            }
            NSLayoutConstraint.activate([
                swatch.widthAnchor.constraint(equalToConstant: 18),
                swatch.heightAnchor.constraint(equalToConstant: 18),
            ])
            historyStack.addArrangedSubview(swatch)
        }
    }
}

// MARK: - NSTextFieldDelegate

extension ColorPickerSidebarView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === hexField else { return }
        if let color = colorFromHex(field.stringValue) {
            selectedColor = color
            colorWheel.setColor(color)
            delegate?.colorPickerSidebarDidSelectColor(color)
        } else {
            field.stringValue = hexString(from: selectedColor)
        }
    }
}

// MARK: - Clickable Swatch

private class ClickableSwatch: NSView {
    var onTap: ((NSColor) -> Void)?
    private let swatchColor: NSColor

    init(color: NSColor) {
        self.swatchColor = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = 3
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.inkBorder.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        onTap?(swatchColor)
    }
}
