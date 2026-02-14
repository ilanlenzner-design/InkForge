import AppKit

protocol BrushSettingsDelegate: AnyObject {
    func brushSettingsDidChange(_ preset: BrushPreset)
}

class BrushSettingsPopover: NSPopover {

    weak var settingsDelegate: BrushSettingsDelegate?
    var brushPreset: BrushPreset = .defaultRound {
        didSet { updateSliders() }
    }

    private var brushTypePopup: NSPopUpButton!
    private var tipTypePopup: NSPopUpButton!
    private var opacitySlider: NSSlider!
    private var flowSlider: NSSlider!
    private var hardnessSlider: NSSlider!
    private var spacingSlider: NSSlider!
    private var streamLineSlider: NSSlider!

    // Conditional rows (shown/hidden based on brush type)
    private var nibAngleRow: NSStackView!
    private var nibAngleSlider: NSSlider!
    private var scatterRow: NSStackView!
    private var scatterSlider: NSSlider!
    private var densityRow: NSStackView!
    private var densitySlider: NSSlider!
    private var grainRow: NSStackView!
    private var grainSlider: NSSlider!

    // Tip type conditional rows
    private var tipTypeRow: NSStackView!
    private var sizeJitterRow: NSStackView!
    private var sizeJitterSlider: NSSlider!
    private var rotJitterRow: NSStackView!
    private var rotJitterSlider: NSSlider!

    private var mainStack: NSStackView!

    private static let typeNames = ["Round", "Pencil", "Calligraphy", "Airbrush",
                                     "Spray", "Marker", "Soft Round"]
    private static let typeMap: [String: BrushPreset.BrushType] = [
        "Round": .round, "Pencil": .pencil, "Calligraphy": .calligraphy,
        "Airbrush": .airbrush, "Spray": .spray, "Marker": .marker,
        "Soft Round": .softRound
    ]
    private static let reverseTypeMap: [BrushPreset.BrushType: String] = [
        .round: "Round", .pencil: "Pencil", .calligraphy: "Calligraphy",
        .airbrush: "Airbrush", .spray: "Spray", .marker: "Marker",
        .softRound: "Soft Round"
    ]

    private static let tipTypeNames = ["Circle", "Dry Brush", "Charcoal", "Ink Splatter",
                                        "Grunge", "Flat Bristle", "Crosshatch"]
    private static let tipTypeMap: [String: BrushPreset.BrushTipType] = [
        "Circle": .circle, "Dry Brush": .dryBrush, "Charcoal": .charcoal,
        "Ink Splatter": .inkSplatter, "Grunge": .grunge,
        "Flat Bristle": .flatBristle, "Crosshatch": .crosshatch
    ]
    private static let reverseTipTypeMap: [BrushPreset.BrushTipType: String] = [
        .circle: "Circle", .dryBrush: "Dry Brush", .charcoal: "Charcoal",
        .inkSplatter: "Ink Splatter", .grunge: "Grunge",
        .flatBristle: "Flat Bristle", .crosshatch: "Crosshatch"
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
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 230, height: 410))

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        mainStack = stack

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
        ])

        // Brush type popup
        let typeRow = NSStackView()
        typeRow.orientation = .horizontal
        typeRow.spacing = 8

        let typeLbl = NSTextField(labelWithString: "Brush:")
        typeLbl.font = .systemFont(ofSize: 11)
        typeLbl.widthAnchor.constraint(equalToConstant: 62).isActive = true
        typeRow.addArrangedSubview(typeLbl)

        brushTypePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        brushTypePopup.controlSize = .small
        brushTypePopup.font = .systemFont(ofSize: 11)
        brushTypePopup.addItems(withTitles: Self.typeNames)
        brushTypePopup.target = self
        brushTypePopup.action = #selector(brushTypeChanged)
        brushTypePopup.widthAnchor.constraint(equalToConstant: 118).isActive = true
        typeRow.addArrangedSubview(brushTypePopup)
        stack.addArrangedSubview(typeRow)

        // Tip type popup
        let tipRow = NSStackView()
        tipRow.orientation = .horizontal
        tipRow.spacing = 8

        let tipLbl = NSTextField(labelWithString: "Tip:")
        tipLbl.font = .systemFont(ofSize: 11)
        tipLbl.widthAnchor.constraint(equalToConstant: 62).isActive = true
        tipRow.addArrangedSubview(tipLbl)

        tipTypePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        tipTypePopup.controlSize = .small
        tipTypePopup.font = .systemFont(ofSize: 11)
        tipTypePopup.addItems(withTitles: Self.tipTypeNames)
        tipTypePopup.target = self
        tipTypePopup.action = #selector(tipTypeChanged)
        tipTypePopup.widthAnchor.constraint(equalToConstant: 118).isActive = true
        tipRow.addArrangedSubview(tipTypePopup)
        stack.addArrangedSubview(tipRow)
        tipTypeRow = tipRow

        // Common sliders
        opacitySlider = makeRow(label: "Opacity:", min: 0, max: 1, value: 1)
        flowSlider = makeRow(label: "Flow:", min: 0, max: 1, value: 1)
        hardnessSlider = makeRow(label: "Hardness:", min: 0, max: 1, value: 0.8)
        spacingSlider = makeRow(label: "Spacing:", min: 0.01, max: 1, value: 0.15)
        streamLineSlider = makeRow(label: "StreamLine:", min: 0, max: 1, value: 0.5)

        // Conditional sliders
        nibAngleSlider = makeConditionalRow(label: "Nib Angle:", min: 0, max: .pi, value: 0.52, row: &nibAngleRow)
        scatterSlider = makeConditionalRow(label: "Scatter:", min: 0, max: 1, value: 1, row: &scatterRow)
        densitySlider = makeConditionalRow(label: "Density:", min: 1, max: 100, value: 30, row: &densityRow)
        grainSlider = makeConditionalRow(label: "Grain:", min: 0, max: 1, value: 0.6, row: &grainRow)

        // Tip jitter sliders (shown when tipType != .circle)
        sizeJitterSlider = makeConditionalRow(label: "Size Jitter:", min: 0, max: 1, value: 0, row: &sizeJitterRow)
        rotJitterSlider = makeConditionalRow(label: "Rot Jitter:", min: 0, max: 1, value: 0, row: &rotJitterRow)

        let vc = NSViewController()
        vc.view = container
        contentViewController = vc
        behavior = .transient
    }

    private func makeRow(label: String, min: Double, max: Double, value: Double) -> NSSlider {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        let lbl = NSTextField(labelWithString: label)
        lbl.font = .systemFont(ofSize: 11)
        lbl.widthAnchor.constraint(equalToConstant: 62).isActive = true
        row.addArrangedSubview(lbl)

        let slider = NSSlider(value: value, minValue: min, maxValue: max,
                               target: self, action: #selector(sliderChanged))
        slider.widthAnchor.constraint(equalToConstant: 118).isActive = true
        row.addArrangedSubview(slider)

        mainStack.addArrangedSubview(row)
        return slider
    }

    private func makeConditionalRow(label: String, min: Double, max: Double,
                                     value: Double, row: inout NSStackView!) -> NSSlider {
        let r = NSStackView()
        r.orientation = .horizontal
        r.spacing = 8

        let lbl = NSTextField(labelWithString: label)
        lbl.font = .systemFont(ofSize: 11)
        lbl.widthAnchor.constraint(equalToConstant: 62).isActive = true
        r.addArrangedSubview(lbl)

        let slider = NSSlider(value: value, minValue: min, maxValue: max,
                               target: self, action: #selector(sliderChanged))
        slider.widthAnchor.constraint(equalToConstant: 118).isActive = true
        r.addArrangedSubview(slider)

        r.isHidden = true
        mainStack.addArrangedSubview(r)
        row = r
        return slider
    }

    @objc private func brushTypeChanged() {
        guard let selected = brushTypePopup.titleOfSelectedItem,
              let newType = Self.typeMap[selected] else { return }
        brushPreset.type = newType
        brushPreset.name = selected
        updateConditionalSliders()
        settingsDelegate?.brushSettingsDidChange(brushPreset)
    }

    @objc private func tipTypeChanged() {
        guard let selected = tipTypePopup.titleOfSelectedItem,
              let newTip = Self.tipTypeMap[selected] else { return }
        brushPreset.tipType = newTip
        updateConditionalSliders()
        settingsDelegate?.brushSettingsDidChange(brushPreset)
    }

    @objc private func sliderChanged() {
        brushPreset.opacity = CGFloat(opacitySlider.doubleValue)
        brushPreset.flow = CGFloat(flowSlider.doubleValue)
        brushPreset.hardness = CGFloat(hardnessSlider.doubleValue)
        brushPreset.spacing = CGFloat(spacingSlider.doubleValue)
        brushPreset.streamLine = CGFloat(streamLineSlider.doubleValue)
        brushPreset.nibAngle = CGFloat(nibAngleSlider.doubleValue)
        brushPreset.scatter = CGFloat(scatterSlider.doubleValue)
        brushPreset.particleDensity = Int(densitySlider.doubleValue)
        brushPreset.grainIntensity = CGFloat(grainSlider.doubleValue)
        brushPreset.sizeJitter = CGFloat(sizeJitterSlider.doubleValue)
        brushPreset.rotationJitter = CGFloat(rotJitterSlider.doubleValue)
        settingsDelegate?.brushSettingsDidChange(brushPreset)
    }

    private func updateSliders() {
        opacitySlider?.doubleValue = Double(brushPreset.opacity)
        flowSlider?.doubleValue = Double(brushPreset.flow)
        hardnessSlider?.doubleValue = Double(brushPreset.hardness)
        spacingSlider?.doubleValue = Double(brushPreset.spacing)
        streamLineSlider?.doubleValue = Double(brushPreset.streamLine)
        nibAngleSlider?.doubleValue = Double(brushPreset.nibAngle)
        scatterSlider?.doubleValue = Double(brushPreset.scatter)
        densitySlider?.doubleValue = Double(brushPreset.particleDensity)
        grainSlider?.doubleValue = Double(brushPreset.grainIntensity)
        sizeJitterSlider?.doubleValue = Double(brushPreset.sizeJitter)
        rotJitterSlider?.doubleValue = Double(brushPreset.rotationJitter)

        // Update type popups
        if let name = Self.reverseTypeMap[brushPreset.type] {
            brushTypePopup?.selectItem(withTitle: name)
        }
        if let tipName = Self.reverseTipTypeMap[brushPreset.tipType] {
            tipTypePopup?.selectItem(withTitle: tipName)
        }

        updateConditionalSliders()
    }

    private func updateConditionalSliders() {
        let type = brushPreset.type
        nibAngleRow?.isHidden = (type != .marker)
        scatterRow?.isHidden = (type != .spray)
        densityRow?.isHidden = (type != .spray)
        grainRow?.isHidden = (type != .pencil)

        let hasTexture = brushPreset.tipType != .circle
        sizeJitterRow?.isHidden = !hasTexture
        rotJitterRow?.isHidden = !hasTexture
    }
}
