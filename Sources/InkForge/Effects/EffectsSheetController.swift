import AppKit

protocol EffectsSheetDelegate: AnyObject {
    func effectsSheetDidApply(_ effects: LayerEffects)
    func effectsSheetDidCancel()
    func effectsSheetDidChangeParams(_ effects: LayerEffects)
}

final class EffectsSheetController: NSViewController {

    weak var delegate: EffectsSheetDelegate?
    var initialEffects = LayerEffects()

    // Enable checkboxes
    private var dropShadowCheck: NSButton!
    private var strokeCheck: NSButton!
    private var outerGlowCheck: NSButton!
    private var innerShadowCheck: NSButton!

    // Drop Shadow controls
    private var dsOffsetX: NSSlider!
    private var dsOffsetY: NSSlider!
    private var dsBlur: NSSlider!
    private var dsOpacity: NSSlider!
    private var dsColor: NSColorWell!

    // Stroke controls
    private var stWidth: NSSlider!
    private var stOpacity: NSSlider!
    private var stColor: NSColorWell!
    private var stPosition: NSPopUpButton!

    // Outer Glow controls
    private var ogBlur: NSSlider!
    private var ogOpacity: NSSlider!
    private var ogColor: NSColorWell!

    // Inner Shadow controls
    private var isOffsetX: NSSlider!
    private var isOffsetY: NSSlider!
    private var isBlur: NSSlider!
    private var isOpacity: NSSlider!
    private var isColor: NSColorWell!

    // Value labels
    private var dsOffsetXLabel: NSTextField!
    private var dsOffsetYLabel: NSTextField!
    private var dsBlurLabel: NSTextField!
    private var dsOpacityLabel: NSTextField!
    private var stWidthLabel: NSTextField!
    private var stOpacityLabel: NSTextField!
    private var ogBlurLabel: NSTextField!
    private var ogOpacityLabel: NSTextField!
    private var isOffsetXLabel: NSTextField!
    private var isOffsetYLabel: NSTextField!
    private var isBlurLabel: NSTextField!
    private var isOpacityLabel: NSTextField!

    override func loadView() {
        let width: CGFloat = 400
        let height: CGFloat = 520
        let buttonBarHeight: CGFloat = 44

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.inkPanel.cgColor
        self.view = container

        // ── Button bar at bottom (always visible) ──
        let buttonBar = NSView(frame: NSRect(x: 0, y: 0, width: width, height: buttonBarHeight))
        buttonBar.wantsLayer = true
        buttonBar.autoresizingMask = [.width]
        container.addSubview(buttonBar)

        let sep = NSBox()
        sep.boxType = .separator
        sep.frame = NSRect(x: 0, y: buttonBarHeight - 1, width: width, height: 1)
        sep.autoresizingMask = [.width]
        buttonBar.addSubview(sep)

        let applyBtn = NSButton(title: "Apply", target: self, action: #selector(applyTapped))
        applyBtn.keyEquivalent = "\r"
        applyBtn.bezelStyle = .rounded
        applyBtn.frame = NSRect(x: width - 90, y: 8, width: 70, height: 28)
        applyBtn.autoresizingMask = [.minXMargin]
        buttonBar.addSubview(applyBtn)

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelBtn.keyEquivalent = "\u{1b}"
        cancelBtn.frame = NSRect(x: width - 170, y: 8, width: 70, height: 28)
        cancelBtn.autoresizingMask = [.minXMargin]
        buttonBar.addSubview(cancelBtn)

        // ── Scroll view above button bar ──
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: buttonBarHeight,
                                                     width: width, height: height - buttonBarHeight))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        container.addSubview(scrollView)

        // ── Scrollable content ──
        let contentHeight: CGFloat = 620
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: contentHeight))

        var y: CGFloat = contentHeight - 20

        // Title
        let title = NSTextField(labelWithString: "Layer Effects")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = .inkText
        title.frame = NSRect(x: 20, y: y, width: 200, height: 20)
        contentView.addSubview(title)
        y -= 34

        // ── Drop Shadow ──
        (dropShadowCheck, y) = addSectionHeader("Drop Shadow", y: y, in: contentView,
                                                  enabled: initialEffects.dropShadow != nil)
        let ds = initialEffects.dropShadow ?? DropShadowEffect()
        (dsOffsetX, dsOffsetXLabel, y) = addSliderRow("Offset X", min: -50, max: 50, value: Double(ds.offsetX), y: y, in: contentView)
        (dsOffsetY, dsOffsetYLabel, y) = addSliderRow("Offset Y", min: -50, max: 50, value: Double(ds.offsetY), y: y, in: contentView)
        (dsBlur, dsBlurLabel, y) = addSliderRow("Blur", min: 0, max: 50, value: Double(ds.blurRadius), y: y, in: contentView)
        (dsOpacity, dsOpacityLabel, y) = addSliderRow("Opacity", min: 0, max: 100, value: Double(ds.opacity * 100), y: y, in: contentView)
        (dsColor, y) = addColorRow("Color", color: NSColor(cgColor: ds.color) ?? .black, y: y, in: contentView)
        y -= 8

        // ── Stroke ──
        (strokeCheck, y) = addSectionHeader("Stroke", y: y, in: contentView,
                                              enabled: initialEffects.stroke != nil)
        let st = initialEffects.stroke ?? StrokeEffect()
        (stWidth, stWidthLabel, y) = addSliderRow("Width", min: 1, max: 20, value: Double(st.width), y: y, in: contentView)
        (stOpacity, stOpacityLabel, y) = addSliderRow("Opacity", min: 0, max: 100, value: Double(st.opacity * 100), y: y, in: contentView)
        (stColor, y) = addColorRow("Color", color: NSColor(cgColor: st.color) ?? .black, y: y, in: contentView)
        (stPosition, y) = addPositionRow("Position", selected: st.position, y: y, in: contentView)
        y -= 8

        // ── Outer Glow ──
        (outerGlowCheck, y) = addSectionHeader("Outer Glow", y: y, in: contentView,
                                                  enabled: initialEffects.outerGlow != nil)
        let og = initialEffects.outerGlow ?? OuterGlowEffect()
        (ogBlur, ogBlurLabel, y) = addSliderRow("Blur", min: 0, max: 50, value: Double(og.blurRadius), y: y, in: contentView)
        (ogOpacity, ogOpacityLabel, y) = addSliderRow("Opacity", min: 0, max: 100, value: Double(og.opacity * 100), y: y, in: contentView)
        (ogColor, y) = addColorRow("Color", color: NSColor(cgColor: og.color) ?? .white, y: y, in: contentView)
        y -= 8

        // ── Inner Shadow ──
        (innerShadowCheck, y) = addSectionHeader("Inner Shadow", y: y, in: contentView,
                                                    enabled: initialEffects.innerShadow != nil)
        let ish = initialEffects.innerShadow ?? InnerShadowEffect()
        (isOffsetX, isOffsetXLabel, y) = addSliderRow("Offset X", min: -20, max: 20, value: Double(ish.offsetX), y: y, in: contentView)
        (isOffsetY, isOffsetYLabel, y) = addSliderRow("Offset Y", min: -20, max: 20, value: Double(ish.offsetY), y: y, in: contentView)
        (isBlur, isBlurLabel, y) = addSliderRow("Blur", min: 0, max: 30, value: Double(ish.blurRadius), y: y, in: contentView)
        (isOpacity, isOpacityLabel, y) = addSliderRow("Opacity", min: 0, max: 100, value: Double(ish.opacity * 100), y: y, in: contentView)
        (isColor, y) = addColorRow("Color", color: NSColor(cgColor: ish.color) ?? .black, y: y, in: contentView)

        scrollView.documentView = contentView

        // Scroll to top
        DispatchQueue.main.async {
            contentView.scroll(NSPoint(x: 0, y: contentHeight))
        }
    }

    // MARK: - Sheet Presentation

    func presentAsSheet(on window: NSWindow) {
        preferredContentSize = NSSize(width: 400, height: 520)
        let sheetWindow = NSWindow(contentViewController: self)
        sheetWindow.styleMask = [.titled]
        window.beginSheet(sheetWindow, completionHandler: nil)
    }

    override func dismiss(_ sender: Any?) {
        if let sheetWindow = view.window, let parent = sheetWindow.sheetParent {
            parent.endSheet(sheetWindow)
        } else {
            super.dismiss(sender)
        }
    }

    // MARK: - Actions

    @objc private func sliderChanged(_ sender: NSSlider) {
        updateValueLabels()
        sendPreview()
    }

    @objc private func checkboxChanged(_ sender: NSButton) {
        sendPreview()
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        sendPreview()
    }

    @objc private func positionChanged(_ sender: NSPopUpButton) {
        sendPreview()
    }

    @objc private func cancelTapped() {
        delegate?.effectsSheetDidCancel()
        dismiss(nil)
    }

    @objc private func applyTapped() {
        delegate?.effectsSheetDidApply(currentEffects())
        dismiss(nil)
    }

    // MARK: - Build Current Effects

    func currentEffects() -> LayerEffects {
        var effects = LayerEffects()

        if dropShadowCheck.state == .on {
            var ds = DropShadowEffect()
            ds.offsetX = CGFloat(dsOffsetX.doubleValue)
            ds.offsetY = CGFloat(dsOffsetY.doubleValue)
            ds.blurRadius = CGFloat(dsBlur.doubleValue)
            ds.opacity = CGFloat(dsOpacity.doubleValue / 100)
            ds.color = dsColor.color.cgColor
            effects.dropShadow = ds
        }

        if strokeCheck.state == .on {
            var st = StrokeEffect()
            st.width = CGFloat(stWidth.doubleValue)
            st.opacity = CGFloat(stOpacity.doubleValue / 100)
            st.color = stColor.color.cgColor
            switch stPosition.indexOfSelectedItem {
            case 0: st.position = .outside
            case 1: st.position = .center
            case 2: st.position = .inside
            default: st.position = .outside
            }
            effects.stroke = st
        }

        if outerGlowCheck.state == .on {
            var og = OuterGlowEffect()
            og.blurRadius = CGFloat(ogBlur.doubleValue)
            og.opacity = CGFloat(ogOpacity.doubleValue / 100)
            og.color = ogColor.color.cgColor
            effects.outerGlow = og
        }

        if innerShadowCheck.state == .on {
            var ish = InnerShadowEffect()
            ish.offsetX = CGFloat(isOffsetX.doubleValue)
            ish.offsetY = CGFloat(isOffsetY.doubleValue)
            ish.blurRadius = CGFloat(isBlur.doubleValue)
            ish.opacity = CGFloat(isOpacity.doubleValue / 100)
            ish.color = isColor.color.cgColor
            effects.innerShadow = ish
        }

        return effects
    }

    private func sendPreview() {
        delegate?.effectsSheetDidChangeParams(currentEffects())
    }

    private func updateValueLabels() {
        dsOffsetXLabel.stringValue = "\(Int(dsOffsetX.doubleValue))"
        dsOffsetYLabel.stringValue = "\(Int(dsOffsetY.doubleValue))"
        dsBlurLabel.stringValue = "\(Int(dsBlur.doubleValue))"
        dsOpacityLabel.stringValue = "\(Int(dsOpacity.doubleValue))%"
        stWidthLabel.stringValue = String(format: "%.1f", stWidth.doubleValue)
        stOpacityLabel.stringValue = "\(Int(stOpacity.doubleValue))%"
        ogBlurLabel.stringValue = "\(Int(ogBlur.doubleValue))"
        ogOpacityLabel.stringValue = "\(Int(ogOpacity.doubleValue))%"
        isOffsetXLabel.stringValue = "\(Int(isOffsetX.doubleValue))"
        isOffsetYLabel.stringValue = "\(Int(isOffsetY.doubleValue))"
        isBlurLabel.stringValue = "\(Int(isBlur.doubleValue))"
        isOpacityLabel.stringValue = "\(Int(isOpacity.doubleValue))%"
    }

    // MARK: - UI Builders

    private func addSectionHeader(_ title: String, y: CGFloat, in container: NSView,
                                   enabled: Bool) -> (NSButton, CGFloat) {
        let check = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkboxChanged(_:)))
        check.font = .systemFont(ofSize: 13, weight: .semibold)
        check.state = enabled ? .on : .off
        check.frame = NSRect(x: 20, y: y, width: 200, height: 20)
        container.addSubview(check)

        let sep = NSBox()
        sep.boxType = .separator
        sep.frame = NSRect(x: 20, y: y - 4, width: 360, height: 1)
        container.addSubview(sep)

        return (check, y - 26)
    }

    private func addSliderRow(_ label: String, min: Double, max: Double, value: Double,
                               y: CGFloat, in container: NSView) -> (NSSlider, NSTextField, CGFloat) {
        let lbl = NSTextField(labelWithString: label)
        lbl.font = .systemFont(ofSize: 12)
        lbl.textColor = .inkTextDim
        lbl.alignment = .right
        lbl.frame = NSRect(x: 30, y: y, width: 65, height: 18)
        container.addSubview(lbl)

        let slider = NSSlider(value: value, minValue: min, maxValue: max,
                               target: self, action: #selector(sliderChanged(_:)))
        slider.isContinuous = true
        slider.frame = NSRect(x: 100, y: y, width: 220, height: 18)
        container.addSubview(slider)

        let fmt: String
        if label == "Opacity" {
            fmt = "\(Int(value))%"
        } else if label == "Width" {
            fmt = String(format: "%.1f", value)
        } else {
            fmt = "\(Int(value))"
        }
        let valueLabel = NSTextField(labelWithString: fmt)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = .inkText
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: 325, y: y, width: 45, height: 18)
        container.addSubview(valueLabel)

        return (slider, valueLabel, y - 24)
    }

    private func addColorRow(_ label: String, color: NSColor, y: CGFloat,
                              in container: NSView) -> (NSColorWell, CGFloat) {
        let lbl = NSTextField(labelWithString: label)
        lbl.font = .systemFont(ofSize: 12)
        lbl.textColor = .inkTextDim
        lbl.alignment = .right
        lbl.frame = NSRect(x: 30, y: y, width: 65, height: 18)
        container.addSubview(lbl)

        let well = NSColorWell(frame: NSRect(x: 100, y: y - 2, width: 40, height: 22))
        well.color = color
        well.target = self
        well.action = #selector(colorChanged(_:))
        container.addSubview(well)

        return (well, y - 28)
    }

    private func addPositionRow(_ label: String, selected: StrokePosition, y: CGFloat,
                                 in container: NSView) -> (NSPopUpButton, CGFloat) {
        let lbl = NSTextField(labelWithString: label)
        lbl.font = .systemFont(ofSize: 12)
        lbl.textColor = .inkTextDim
        lbl.alignment = .right
        lbl.frame = NSRect(x: 30, y: y, width: 65, height: 18)
        container.addSubview(lbl)

        let popup = NSPopUpButton(frame: NSRect(x: 100, y: y - 2, width: 120, height: 22), pullsDown: false)
        popup.controlSize = .small
        popup.font = .systemFont(ofSize: 11)
        popup.addItem(withTitle: "Outside")
        popup.addItem(withTitle: "Center")
        popup.addItem(withTitle: "Inside")
        popup.target = self
        popup.action = #selector(positionChanged(_:))

        switch selected {
        case .outside: popup.selectItem(at: 0)
        case .center: popup.selectItem(at: 1)
        case .inside: popup.selectItem(at: 2)
        }

        container.addSubview(popup)
        return (popup, y - 28)
    }
}
