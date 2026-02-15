import AppKit

protocol LayerPanelDelegate: AnyObject {
    func layerPanelDidSelectLayer(at index: Int)
    func layerPanelDidAddLayer()
    func layerPanelDidDeleteLayer(at index: Int)
    func layerPanelDidToggleVisibility(at index: Int)
    func layerPanelDidMergeDown(at index: Int)
    func layerPanelDidChangeOpacity(at index: Int, opacity: CGFloat)
    func layerPanelDidToggleAlphaLock(at index: Int)
    func layerPanelDidToggleClippingMask(at index: Int)
    func layerPanelDidChangeBlendMode(at index: Int, mode: CGBlendMode)
    func layerPanelDidMoveLayer(from src: Int, to dst: Int)
    func layerPanelDidToggleReferenceLayer(at index: Int)
    func layerPanelDidToggleMask(at index: Int)
    func layerPanelDidToggleMaskEditing(at index: Int)
    func layerPanelDidRasterize(at index: Int)
    func layerPanelDidConvertToMask(at index: Int)
    func layerPanelDidApplyMask(at index: Int)
    func layerPanelDidRequestEffects(at index: Int)
}

class LayerPanelView: NSView {

    weak var delegate: LayerPanelDelegate?
    var layerStack: LayerStack? {
        didSet { reload() }
    }

    private var scrollView: NSScrollView!
    private var layerListView: NSStackView!
    private var opacitySlider: NSSlider!
    private var opacityLabel: NSTextField!
    private var alphaLockBtn: NSButton!
    private var clipMaskBtn: NSButton!
    private var refLayerBtn: NSButton!
    private var maskBtn: NSButton!
    private var fxBtn: NSButton!
    private var blendModePopup: NSPopUpButton!
    private let thumbSize: CGFloat = 52

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
        layer?.backgroundColor = NSColor.inkPanelAlt.cgColor

        // Left border
        let leftBorder = CALayer()
        leftBorder.backgroundColor = NSColor.inkBorder.cgColor
        leftBorder.frame = CGRect(x: 0, y: 0, width: 1, height: 10000)
        leftBorder.autoresizingMask = [.layerHeightSizable]
        layer?.addSublayer(leftBorder)

        // Title
        let title = NSTextField(labelWithString: "LAYERS")
        title.font = .systemFont(ofSize: 11, weight: .bold)
        title.textColor = .inkTextDim
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        // -- Top controls: Blend mode + Opacity --
        blendModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        blendModePopup.controlSize = .small
        blendModePopup.font = .systemFont(ofSize: 11)
        for name in Self.blendModeNames {
            blendModePopup.addItem(withTitle: name)
        }
        blendModePopup.target = self
        blendModePopup.action = #selector(blendModeChanged(_:))
        blendModePopup.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blendModePopup)

        let opacityRow = NSStackView()
        opacityRow.orientation = .horizontal
        opacityRow.spacing = 6
        opacityRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(opacityRow)

        let opacityTitle = NSTextField(labelWithString: "Opacity")
        opacityTitle.font = .systemFont(ofSize: 11, weight: .medium)
        opacityTitle.textColor = .inkTextDim
        opacityRow.addArrangedSubview(opacityTitle)

        opacitySlider = NSSlider(value: 1.0, minValue: 0.0, maxValue: 1.0,
                                  target: self, action: #selector(opacityChanged(_:)))
        opacitySlider.controlSize = .small
        opacityRow.addArrangedSubview(opacitySlider)

        opacityLabel = NSTextField(labelWithString: "100%")
        opacityLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        opacityLabel.textColor = .inkText
        opacityLabel.alignment = .right
        opacityLabel.translatesAutoresizingMaskIntoConstraints = false
        opacityRow.addArrangedSubview(opacityLabel)

        // -- Property toggles row (bigger, with icons) --
        let propRow = NSStackView()
        propRow.orientation = .horizontal
        propRow.spacing = 4
        propRow.distribution = .fillEqually
        propRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(propRow)

        alphaLockBtn = makeToggleButton(symbol: "lock", label: "\u{03B1}Lock",
                                         action: #selector(alphaLockClicked), tooltip: "Alpha Lock")
        clipMaskBtn = makeToggleButton(symbol: "paperclip", label: "Clip",
                                        action: #selector(clipMaskClicked), tooltip: "Clipping Mask")
        refLayerBtn = makeToggleButton(symbol: "scope", label: "Ref",
                                        action: #selector(refLayerClicked), tooltip: "Reference Layer (for Fill)")
        maskBtn = makeToggleButton(symbol: "theatermasks", label: "Mask",
                                    action: #selector(maskClicked), tooltip: "Toggle Layer Mask")
        fxBtn = makeToggleButton(symbol: "sparkles", label: "FX",
                                  action: #selector(fxClicked), tooltip: "Layer Effects")
        propRow.addArrangedSubview(alphaLockBtn)
        propRow.addArrangedSubview(clipMaskBtn)
        propRow.addArrangedSubview(refLayerBtn)
        propRow.addArrangedSubview(maskBtn)
        propRow.addArrangedSubview(fxBtn)

        // -- Scroll view for layer list (middle, flexible) --
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .inkPanel
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        layerListView = NSStackView()
        layerListView.orientation = .vertical
        layerListView.spacing = 2
        layerListView.alignment = .leading
        layerListView.translatesAutoresizingMaskIntoConstraints = false

        let clipView = NSClipView()
        clipView.drawsBackground = true
        clipView.backgroundColor = .inkPanel
        clipView.documentView = layerListView
        scrollView.contentView = clipView

        // -- Bottom action bar: +, −, Merge, ▲, ▼ --
        let bottomBar = NSStackView()
        bottomBar.orientation = .horizontal
        bottomBar.spacing = 4
        bottomBar.distribution = .fillEqually
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomBar)

        // Top border for bottom bar
        let barBorder = CALayer()
        barBorder.backgroundColor = NSColor.inkBorder.cgColor
        barBorder.frame = CGRect(x: 0, y: 0, width: 10000, height: 1)
        barBorder.autoresizingMask = [.layerWidthSizable, .layerMaxYMargin]
        bottomBar.wantsLayer = true
        bottomBar.layer?.addSublayer(barBorder)

        let addBtn = makeActionButton(symbol: "plus", action: #selector(addLayerClicked), tooltip: "Add Layer")
        let delBtn = makeActionButton(symbol: "trash", action: #selector(deleteLayerClicked), tooltip: "Delete Layer")
        let mergeBtn = makeActionButton(symbol: "arrow.down.on.square", action: #selector(mergeDownClicked), tooltip: "Merge Down")
        let rasterizeBtn = makeActionButton(symbol: "square.grid.3x3", action: #selector(rasterizeClicked), tooltip: "Rasterize Text Layer")
        let moveUpBtn = makeActionButton(symbol: "chevron.up", action: #selector(moveLayerUpClicked), tooltip: "Move Layer Up")
        let moveDownBtn = makeActionButton(symbol: "chevron.down", action: #selector(moveLayerDownClicked), tooltip: "Move Layer Down")
        bottomBar.addArrangedSubview(addBtn)
        bottomBar.addArrangedSubview(delBtn)
        bottomBar.addArrangedSubview(mergeBtn)
        bottomBar.addArrangedSubview(rasterizeBtn)
        bottomBar.addArrangedSubview(moveUpBtn)
        bottomBar.addArrangedSubview(moveDownBtn)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            blendModePopup.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            blendModePopup.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            blendModePopup.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            opacityRow.topAnchor.constraint(equalTo: blendModePopup.bottomAnchor, constant: 6),
            opacityRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            opacityRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            opacityLabel.widthAnchor.constraint(equalToConstant: 38),

            propRow.topAnchor.constraint(equalTo: opacityRow.bottomAnchor, constant: 8),
            propRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            propRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            propRow.heightAnchor.constraint(equalToConstant: 32),

            scrollView.topAnchor.constraint(equalTo: propRow.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            layerListView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            bottomBar.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    private func makeToggleButton(symbol: String, label: String, action: Selector, tooltip: String) -> NSButton {
        let btn = NSButton(title: label, target: self, action: action)
        btn.bezelStyle = .smallSquare
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor.inkBtnBg.cgColor
        btn.layer?.cornerRadius = 6
        btn.layer?.borderWidth = 1
        btn.layer?.borderColor = NSColor.inkBorder.cgColor
        btn.font = .systemFont(ofSize: 10, weight: .semibold)
        btn.contentTintColor = .inkText
        btn.toolTip = tooltip
        return btn
    }

    private func makeActionButton(symbol: String, action: Selector, tooltip: String) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .smallSquare
        btn.setButtonType(.momentaryPushIn)
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor.inkBtnBg.cgColor
        btn.layer?.cornerRadius = 6
        btn.layer?.borderWidth = 1
        btn.layer?.borderColor = NSColor.inkBorder.cgColor
        btn.target = self
        btn.action = action
        btn.toolTip = tooltip

        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            btn.image = img.withSymbolConfiguration(config) ?? img
            btn.imagePosition = .imageOnly
            btn.contentTintColor = .inkText
        } else {
            btn.title = String(tooltip.prefix(3))
            btn.font = .systemFont(ofSize: 12, weight: .medium)
            btn.contentTintColor = .inkText
        }
        return btn
    }

    func reload() {
        guard let stack = layerStack else { return }

        // Update controls for active layer
        if let activeLayer = stack.activeLayer {
            opacitySlider.doubleValue = activeLayer.opacity
            opacityLabel.stringValue = "\(Int(activeLayer.opacity * 100))%"
            alphaLockBtn.state = activeLayer.isAlphaLocked ? .on : .off
            updateToggleStyle(alphaLockBtn, active: activeLayer.isAlphaLocked, color: .inkAccent)
            clipMaskBtn.state = activeLayer.isClippingMask ? .on : .off
            updateToggleStyle(clipMaskBtn, active: activeLayer.isClippingMask, color: .inkAccent)
            refLayerBtn.state = activeLayer.isReferenceLayer ? .on : .off
            updateToggleStyle(refLayerBtn, active: activeLayer.isReferenceLayer, color: .systemOrange)
            maskBtn.state = activeLayer.hasMask ? .on : .off
            updateToggleStyle(maskBtn, active: activeLayer.hasMask, color: activeLayer.isMaskEditing ? .systemGreen : .inkAccent)
            updateToggleStyle(fxBtn, active: activeLayer.effects.hasAny, color: .systemPurple)
            if let idx = Self.blendModes.firstIndex(of: activeLayer.blendMode) {
                blendModePopup.selectItem(at: idx)
            }
        }

        // Remove old views
        for view in layerListView.arrangedSubviews {
            layerListView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        // Add layers in reverse order (top layer first)
        for i in stride(from: stack.layers.count - 1, through: 0, by: -1) {
            let layer = stack.layers[i]
            let row = makeLayerRow(layer: layer, index: i,
                                    isActive: i == stack.activeLayerIndex)
            layerListView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: layerListView.widthAnchor).isActive = true
        }
    }

    private func updateToggleStyle(_ btn: NSButton, active: Bool, color: NSColor) {
        if active {
            btn.layer?.backgroundColor = color.withAlphaComponent(0.2).cgColor
            btn.layer?.borderColor = color.cgColor
            btn.contentTintColor = color
        } else {
            btn.layer?.backgroundColor = NSColor.inkBtnBg.cgColor
            btn.layer?.borderColor = NSColor.inkBorder.cgColor
            btn.contentTintColor = .inkText
        }
    }

    private func makeLayerRow(layer: Layer, index: Int, isActive: Bool) -> NSView {
        let rowHeight: CGFloat = 64

        let row = NSView()
        row.wantsLayer = true
        if isActive {
            row.layer?.backgroundColor = NSColor.inkActiveBg.cgColor
            row.layer?.borderWidth = 1
            row.layer?.borderColor = NSColor.inkAccent.cgColor
            row.layer?.cornerRadius = 6
        } else {
            row.layer?.backgroundColor = NSColor.inkPanel.cgColor
            row.layer?.cornerRadius = 4
        }
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true

        // --- Eye icon (visibility toggle) ---
        let eyeBtn = NSButton(frame: .zero)
        eyeBtn.bezelStyle = .toolbar
        eyeBtn.setButtonType(.toggle)
        eyeBtn.isBordered = false
        eyeBtn.tag = index
        eyeBtn.target = self
        eyeBtn.action = #selector(visibilityToggled(_:))
        eyeBtn.state = layer.isVisible ? .on : .off
        eyeBtn.toolTip = layer.isVisible ? "Hide Layer" : "Show Layer"
        eyeBtn.translatesAutoresizingMaskIntoConstraints = false

        let eyeSymbol = layer.isVisible ? "eye.fill" : "eye.slash"
        if let img = NSImage(systemSymbolName: eyeSymbol, accessibilityDescription: "Visibility") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            eyeBtn.image = img.withSymbolConfiguration(config) ?? img
        } else {
            eyeBtn.title = layer.isVisible ? "V" : "-"
        }
        eyeBtn.contentTintColor = layer.isVisible ? .inkAccent : .inkTextMuted

        // --- Thumbnail ---
        let thumbView = NSImageView()
        thumbView.wantsLayer = true
        thumbView.layer?.backgroundColor = NSColor.white.cgColor
        thumbView.layer?.borderWidth = 1
        thumbView.layer?.borderColor = NSColor.inkBorder.cgColor
        thumbView.layer?.cornerRadius = 4
        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.translatesAutoresizingMaskIntoConstraints = false

        if let cgImage = layer.makeImage() {
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: thumbSize, height: thumbSize))
            let flipped = NSImage(size: NSSize(width: thumbSize, height: thumbSize), flipped: true) { rect in
                nsImage.draw(in: rect)
                return true
            }
            thumbView.image = flipped
        }

        // --- Mask thumbnail (if mask exists) ---
        var maskThumbView: NSImageView?
        if layer.hasMask {
            let mv = NSImageView()
            mv.wantsLayer = true
            mv.layer?.backgroundColor = NSColor.black.cgColor
            mv.layer?.borderWidth = layer.isMaskEditing ? 2 : 1
            mv.layer?.borderColor = layer.isMaskEditing ? NSColor.systemGreen.cgColor : NSColor.inkBorder.cgColor
            mv.layer?.cornerRadius = 3
            mv.imageScaling = .scaleProportionallyUpOrDown
            mv.translatesAutoresizingMaskIntoConstraints = false

            if let maskImg = layer.makeMaskImage() {
                let nsImg = NSImage(cgImage: maskImg, size: NSSize(width: 30, height: 30))
                let flipped = NSImage(size: NSSize(width: 30, height: 30), flipped: true) { rect in
                    nsImg.draw(in: rect)
                    return true
                }
                mv.image = flipped
            }

            // Click to toggle mask editing
            let maskClickBtn = NSButton(title: "", target: self, action: #selector(maskThumbClicked(_:)))
            maskClickBtn.tag = index
            maskClickBtn.isTransparent = true
            maskClickBtn.translatesAutoresizingMaskIntoConstraints = false
            mv.addSubview(maskClickBtn)
            NSLayoutConstraint.activate([
                maskClickBtn.leadingAnchor.constraint(equalTo: mv.leadingAnchor),
                maskClickBtn.trailingAnchor.constraint(equalTo: mv.trailingAnchor),
                maskClickBtn.topAnchor.constraint(equalTo: mv.topAnchor),
                maskClickBtn.bottomAnchor.constraint(equalTo: mv.bottomAnchor),
            ])

            maskThumbView = mv
        }

        // --- Layer name ---
        let nameLabel = NSTextField(labelWithString: layer.name)
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = .inkText
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        // --- "T" badge for text layers ---
        if layer.isTextLayer {
            let badge = NSTextField(labelWithString: "T")
            badge.font = .systemFont(ofSize: 14, weight: .bold)
            badge.textColor = .systemBlue
            badge.backgroundColor = NSColor.white.withAlphaComponent(0.85)
            badge.isBezeled = false
            badge.isEditable = false
            badge.drawsBackground = true
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 3
            badge.alignment = .center
            badge.translatesAutoresizingMaskIntoConstraints = false
            thumbView.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.trailingAnchor.constraint(equalTo: thumbView.trailingAnchor, constant: -2),
                badge.bottomAnchor.constraint(equalTo: thumbView.bottomAnchor, constant: -2),
                badge.widthAnchor.constraint(equalToConstant: 16),
                badge.heightAnchor.constraint(equalToConstant: 16),
            ])
        }

        // --- Status label (opacity + flags) ---
        var statusParts: [String] = ["\(Int(layer.opacity * 100))%"]
        if layer.isTextLayer { statusParts.append("Text") }
        if layer.isAlphaLocked { statusParts.append("\u{03B1}Lock") }
        if layer.isClippingMask { statusParts.append("Clip") }
        if layer.isReferenceLayer { statusParts.append("Ref") }
        if layer.hasMask { statusParts.append(layer.isMaskEditing ? "Editing Mask" : "Mask") }
        if layer.effects.hasAny { statusParts.append("FX") }
        let statusLabel = NSTextField(labelWithString: statusParts.joined(separator: " \u{00B7} "))
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .inkTextDim
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        // --- Lock indicator ---
        if layer.isLocked {
            let lockLabel = NSTextField(labelWithString: "Locked")
            lockLabel.font = .systemFont(ofSize: 10)
            lockLabel.textColor = .inkTextMuted
            lockLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(lockLabel)
            NSLayoutConstraint.activate([
                lockLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
                lockLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -6),
            ])
        }

        // --- Right-click context menu ---
        let menu = NSMenu()
        let convertItem = NSMenuItem(title: "Convert to Mask", action: #selector(convertToMaskClicked(_:)), keyEquivalent: "")
        convertItem.target = self
        convertItem.tag = index
        convertItem.isEnabled = index > 0  // needs a layer below
        menu.addItem(convertItem)

        let applyMaskItem = NSMenuItem(title: "Apply Mask", action: #selector(applyMaskClicked(_:)), keyEquivalent: "")
        applyMaskItem.target = self
        applyMaskItem.tag = index
        applyMaskItem.isEnabled = layer.hasMask
        menu.addItem(applyMaskItem)

        row.menu = menu

        // --- Invisible click target for selection ---
        let selectBtn = NSButton(title: "", target: self, action: #selector(layerSelected(_:)))
        selectBtn.tag = index
        selectBtn.isTransparent = true
        selectBtn.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(eyeBtn)
        row.addSubview(thumbView)
        row.addSubview(nameLabel)
        row.addSubview(statusLabel)
        row.addSubview(selectBtn)

        // The anchor after the thumbnails (changes if mask thumb exists)
        var textLeadingAnchor = thumbView.trailingAnchor

        if let mv = maskThumbView {
            row.addSubview(mv)
            NSLayoutConstraint.activate([
                mv.leadingAnchor.constraint(equalTo: thumbView.trailingAnchor, constant: 4),
                mv.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                mv.widthAnchor.constraint(equalToConstant: 30),
                mv.heightAnchor.constraint(equalToConstant: thumbSize),
            ])
            textLeadingAnchor = mv.trailingAnchor
        }

        NSLayoutConstraint.activate([
            // Eye button on the left
            eyeBtn.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 6),
            eyeBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            eyeBtn.widthAnchor.constraint(equalToConstant: 24),
            eyeBtn.heightAnchor.constraint(equalToConstant: 24),

            // Thumbnail next to eye
            thumbView.leadingAnchor.constraint(equalTo: eyeBtn.trailingAnchor, constant: 6),
            thumbView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            thumbView.widthAnchor.constraint(equalToConstant: thumbSize),
            thumbView.heightAnchor.constraint(equalToConstant: thumbSize),

            // Name to the right of last thumbnail
            nameLabel.leadingAnchor.constraint(equalTo: textLeadingAnchor, constant: 8),
            nameLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -8),

            // Status below name
            statusLabel.leadingAnchor.constraint(equalTo: textLeadingAnchor, constant: 8),
            statusLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 3),

            // Select button covers entire row (behind eye button)
            selectBtn.leadingAnchor.constraint(equalTo: thumbView.leadingAnchor),
            selectBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            selectBtn.topAnchor.constraint(equalTo: row.topAnchor),
            selectBtn.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])

        return row
    }

    @objc private func addLayerClicked() {
        delegate?.layerPanelDidAddLayer()
    }

    @objc private func deleteLayerClicked() {
        guard let stack = layerStack else { return }
        delegate?.layerPanelDidDeleteLayer(at: stack.activeLayerIndex)
    }

    @objc private func mergeDownClicked() {
        guard let stack = layerStack else { return }
        delegate?.layerPanelDidMergeDown(at: stack.activeLayerIndex)
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        guard let stack = layerStack else { return }
        let opacity = CGFloat(sender.doubleValue)
        opacityLabel.stringValue = "\(Int(opacity * 100))%"
        delegate?.layerPanelDidChangeOpacity(at: stack.activeLayerIndex, opacity: opacity)
    }

    @objc private func visibilityToggled(_ sender: NSButton) {
        delegate?.layerPanelDidToggleVisibility(at: sender.tag)
    }

    @objc private func layerSelected(_ sender: NSButton) {
        delegate?.layerPanelDidSelectLayer(at: sender.tag)
    }

    @objc private func alphaLockClicked() {
        guard let stack = layerStack else { return }
        delegate?.layerPanelDidToggleAlphaLock(at: stack.activeLayerIndex)
    }

    @objc private func clipMaskClicked() {
        guard let stack = layerStack else { return }
        delegate?.layerPanelDidToggleClippingMask(at: stack.activeLayerIndex)
    }

    @objc private func refLayerClicked() {
        guard let stack = layerStack else { return }
        delegate?.layerPanelDidToggleReferenceLayer(at: stack.activeLayerIndex)
    }

    @objc private func maskClicked() {
        guard let stack = layerStack else { return }
        delegate?.layerPanelDidToggleMask(at: stack.activeLayerIndex)
    }

    @objc private func fxClicked() {
        guard let stack = layerStack else { return }
        delegate?.layerPanelDidRequestEffects(at: stack.activeLayerIndex)
    }

    @objc private func maskThumbClicked(_ sender: NSButton) {
        delegate?.layerPanelDidToggleMaskEditing(at: sender.tag)
    }

    @objc private func convertToMaskClicked(_ sender: NSMenuItem) {
        delegate?.layerPanelDidConvertToMask(at: sender.tag)
    }

    @objc private func applyMaskClicked(_ sender: NSMenuItem) {
        delegate?.layerPanelDidApplyMask(at: sender.tag)
    }

    @objc private func rasterizeClicked() {
        guard let stack = layerStack else { return }
        delegate?.layerPanelDidRasterize(at: stack.activeLayerIndex)
    }

    @objc private func moveLayerUpClicked() {
        guard let stack = layerStack else { return }
        let idx = stack.activeLayerIndex
        guard idx < stack.layers.count - 1 else { return }
        delegate?.layerPanelDidMoveLayer(from: idx, to: idx + 1)
    }

    @objc private func moveLayerDownClicked() {
        guard let stack = layerStack else { return }
        let idx = stack.activeLayerIndex
        guard idx > 0 else { return }
        delegate?.layerPanelDidMoveLayer(from: idx, to: idx - 1)
    }

    @objc private func blendModeChanged(_ sender: NSPopUpButton) {
        guard let stack = layerStack else { return }
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < Self.blendModes.count else { return }
        delegate?.layerPanelDidChangeBlendMode(at: stack.activeLayerIndex,
                                                mode: Self.blendModes[idx])
    }

    // MARK: - Blend Modes

    static let blendModeNames = [
        "Normal", "Multiply", "Screen", "Overlay",
        "Darken", "Lighten", "Color Dodge", "Color Burn",
        "Soft Light", "Hard Light", "Difference", "Exclusion"
    ]

    static let blendModes: [CGBlendMode] = [
        .normal, .multiply, .screen, .overlay,
        .darken, .lighten, .colorDodge, .colorBurn,
        .softLight, .hardLight, .difference, .exclusion
    ]
}
