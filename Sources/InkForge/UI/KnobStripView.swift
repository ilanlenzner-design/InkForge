import AppKit

protocol KnobStripDelegate: AnyObject {
    func knobStripDidChangeRotation(_ degrees: CGFloat)
    func knobStripDidChangeZoom(_ scale: CGFloat)
    func knobStripDidChangeBrushSize(_ size: CGFloat)
}

class KnobStripView: NSView {

    weak var delegate: KnobStripDelegate?

    private(set) var rotationKnob: KnobControl!
    private(set) var zoomKnob: KnobControl!
    private(set) var brushSizeKnob: KnobControl!

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

        // Rotation knob: -180…180 degrees
        rotationKnob = makeKnob(min: -180, max: 180, defaultVal: 0,
                                 sensitivity: 0.005, label: "Rotate")
        rotationKnob.formattedValue = "0°"
        rotationKnob.target = self
        rotationKnob.action = #selector(rotationChanged)

        // Zoom knob: log2 scale, -4.32 (5%) … 5.0 (3200%)
        zoomKnob = makeKnob(min: log2(0.05), max: log2(32), defaultVal: 0,
                             sensitivity: 0.003, label: "Zoom")
        zoomKnob.formattedValue = "100%"
        zoomKnob.target = self
        zoomKnob.action = #selector(zoomChanged)

        // Brush size knob: 1…200
        brushSizeKnob = makeKnob(min: 1, max: 200, defaultVal: 12,
                                  sensitivity: 0.008, label: "Size")
        brushSizeKnob.value = 12
        brushSizeKnob.formattedValue = "12"
        brushSizeKnob.target = self
        brushSizeKnob.action = #selector(brushSizeChanged)

        let stack = NSStackView(views: [rotationKnob, zoomKnob, brushSizeKnob])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
        ])
    }

    private func makeKnob(min: CGFloat, max: CGFloat, defaultVal: CGFloat,
                           sensitivity: CGFloat, label: String) -> KnobControl {
        let knob = KnobControl()
        knob.minValue = min
        knob.maxValue = max
        knob.defaultValue = defaultVal
        knob.value = defaultVal
        knob.sensitivity = sensitivity
        knob.label = label
        knob.translatesAutoresizingMaskIntoConstraints = false
        return knob
    }

    // MARK: - Actions

    @objc private func rotationChanged() {
        rotationKnob.formattedValue = "\(Int(rotationKnob.value))°"
        rotationKnob.needsDisplay = true
        delegate?.knobStripDidChangeRotation(rotationKnob.value)
    }

    @objc private func zoomChanged() {
        let scale = pow(2, zoomKnob.value)
        zoomKnob.formattedValue = "\(Int(scale * 100))%"
        zoomKnob.needsDisplay = true
        delegate?.knobStripDidChangeZoom(scale)
    }

    @objc private func brushSizeChanged() {
        let size = round(brushSizeKnob.value)
        brushSizeKnob.formattedValue = "\(Int(size))"
        brushSizeKnob.needsDisplay = true
        delegate?.knobStripDidChangeBrushSize(size)
    }

    // MARK: - External Update Methods

    func updateRotation(_ degrees: CGFloat) {
        rotationKnob.value = degrees
        rotationKnob.formattedValue = "\(Int(degrees))°"
    }

    func updateZoom(_ scale: CGFloat) {
        zoomKnob.value = log2(scale)
        zoomKnob.formattedValue = "\(Int(scale * 100))%"
    }

    func updateBrushSize(_ size: CGFloat) {
        brushSizeKnob.value = size
        brushSizeKnob.formattedValue = "\(Int(size))"
    }
}
