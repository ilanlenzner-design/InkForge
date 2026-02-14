import AppKit

class StatusBarView: NSView {

    private var zoomLabel: NSTextField!
    private var positionLabel: NSTextField!
    private var toolLabel: NSTextField!
    private var pressureLabel: NSTextField!

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

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        toolLabel = makeStatusItem(symbol: "pencil.tip", text: "Pen", stack: stack)
        zoomLabel = makeStatusItem(symbol: "magnifyingglass", text: "100%", stack: stack)
        positionLabel = makeStatusItem(symbol: "scope", text: "0, 0", stack: stack)
        pressureLabel = makeStatusItem(symbol: "hand.draw", text: "0.00", stack: stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func makeStatusItem(symbol: String, text: String, stack: NSStackView) -> NSTextField {
        let container = NSStackView()
        container.orientation = .horizontal
        container.spacing = 5
        container.translatesAutoresizingMaskIntoConstraints = false

        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            let iconView = NSImageView(image: img.withSymbolConfiguration(config) ?? img)
            iconView.contentTintColor = .inkTextDim
            iconView.translatesAutoresizingMaskIntoConstraints = false
            container.addArrangedSubview(iconView)
        }

        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .inkText
        container.addArrangedSubview(label)

        stack.addArrangedSubview(container)
        return label
    }

    func updateZoom(_ percent: Int) {
        zoomLabel.stringValue = "\(percent)%"
    }

    func updatePosition(x: Int, y: Int) {
        positionLabel.stringValue = "\(x), \(y)"
    }

    func updateTool(_ name: String) {
        toolLabel.stringValue = name
    }

    func updatePressure(_ value: CGFloat) {
        pressureLabel.stringValue = String(format: "%.2f", value)
    }
}
