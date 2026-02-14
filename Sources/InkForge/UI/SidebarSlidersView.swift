import AppKit

protocol SidebarSlidersDelegate: AnyObject {
    func sidebarDidChangeBrushSize(_ size: CGFloat)
    func sidebarDidChangeOpacity(_ opacity: CGFloat)
}

class SidebarSlidersView: NSView {

    weak var delegate: SidebarSlidersDelegate?

    private var sizeSlider: NeumorphicVerticalSlider!
    private var opacitySlider: NeumorphicVerticalSlider!
    private var sizeValueLabel: NSTextField!
    private var opacityValueLabel: NSTextField!

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

        // Size section
        let sizeTitle = makeTitle("Size")
        sizeValueLabel = makeValueLabel("12")
        sizeSlider = NeumorphicVerticalSlider()
        sizeSlider.minValue = 1
        sizeSlider.maxValue = 200
        sizeSlider.value = 12
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged)
        sizeSlider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sizeSlider)

        // Separator
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.inkBorder.cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)

        // Opacity section
        let opacityTitle = makeTitle("Opacity")
        opacityValueLabel = makeValueLabel("100%")
        opacitySlider = NeumorphicVerticalSlider()
        opacitySlider.minValue = 1
        opacitySlider.maxValue = 100
        opacitySlider.value = 100
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged)
        opacitySlider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(opacitySlider)

        NSLayoutConstraint.activate([
            sizeTitle.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            sizeTitle.centerXAnchor.constraint(equalTo: centerXAnchor),

            sizeValueLabel.topAnchor.constraint(equalTo: sizeTitle.bottomAnchor, constant: 2),
            sizeValueLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            sizeSlider.topAnchor.constraint(equalTo: sizeValueLabel.bottomAnchor, constant: 8),
            sizeSlider.centerXAnchor.constraint(equalTo: centerXAnchor),
            sizeSlider.widthAnchor.constraint(equalToConstant: 36),
            sizeSlider.bottomAnchor.constraint(equalTo: sep.topAnchor, constant: -10),

            sep.centerYAnchor.constraint(equalTo: centerYAnchor),
            sep.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            sep.heightAnchor.constraint(equalToConstant: 1),

            opacityTitle.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 10),
            opacityTitle.centerXAnchor.constraint(equalTo: centerXAnchor),

            opacityValueLabel.topAnchor.constraint(equalTo: opacityTitle.bottomAnchor, constant: 2),
            opacityValueLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            opacitySlider.topAnchor.constraint(equalTo: opacityValueLabel.bottomAnchor, constant: 8),
            opacitySlider.centerXAnchor.constraint(equalTo: centerXAnchor),
            opacitySlider.widthAnchor.constraint(equalToConstant: 36),
            opacitySlider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    private func makeTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .inkText
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        return label
    }

    private func makeValueLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .inkTextDim
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        return label
    }

    // MARK: - Actions

    @objc private func sizeChanged() {
        let size = sizeSlider.value
        sizeValueLabel.stringValue = "\(Int(size))"
        delegate?.sidebarDidChangeBrushSize(size)
    }

    @objc private func opacityChanged() {
        let opacity = opacitySlider.value
        opacityValueLabel.stringValue = "\(Int(opacity))%"
        delegate?.sidebarDidChangeOpacity(opacity / 100.0)
    }

    // MARK: - Updates

    func updateBrushSize(_ size: CGFloat) {
        sizeSlider?.value = size
        sizeValueLabel?.stringValue = "\(Int(size))"
    }

    func updateOpacity(_ opacity: CGFloat) {
        let pct = Int(opacity * 100)
        opacitySlider?.value = CGFloat(pct)
        opacityValueLabel?.stringValue = "\(pct)%"
    }
}
