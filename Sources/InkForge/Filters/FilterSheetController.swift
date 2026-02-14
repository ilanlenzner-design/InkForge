import AppKit

protocol FilterSheetDelegate: AnyObject {
    func filterSheetDidApply(_ filter: FilterType, params: [String: Double])
    func filterSheetDidCancel()
    func filterSheetDidChangeParams(_ filter: FilterType, params: [String: Double])
}

final class FilterSheetController: NSViewController {

    weak var delegate: FilterSheetDelegate?
    let filterType: FilterType

    private var sliders: [(key: String, slider: NSSlider, valueLabel: NSTextField)] = []

    init(filter: FilterType) {
        self.filterType = filter
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let params = filterType.parameters
        let rowCount = params.count
        let height = CGFloat(60 + rowCount * 40 + 60)
        let width: CGFloat = 360

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.inkPanel.cgColor
        self.view = container

        // Title
        let title = NSTextField(labelWithString: filterType.displayName)
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = .inkText
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
        ])

        // Slider rows
        var lastAnchor = title.bottomAnchor

        for param in params {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(row)

            let label = NSTextField(labelWithString: param.label)
            label.font = .systemFont(ofSize: 13)
            label.textColor = .inkTextDim
            label.alignment = .right
            row.addArrangedSubview(label)

            let slider = NSSlider(value: param.defaultValue,
                                   minValue: param.min, maxValue: param.max,
                                   target: self, action: #selector(sliderChanged(_:)))
            slider.isContinuous = true
            slider.translatesAutoresizingMaskIntoConstraints = false
            row.addArrangedSubview(slider)

            let valueLabel = NSTextField(labelWithString: formatValue(param.defaultValue, param: param))
            valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            valueLabel.textColor = .inkText
            valueLabel.alignment = .right
            row.addArrangedSubview(valueLabel)

            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: lastAnchor, constant: 12),
                row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
                row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
                label.widthAnchor.constraint(equalToConstant: 80),
                valueLabel.widthAnchor.constraint(equalToConstant: 50),
            ])

            sliders.append((key: param.key, slider: slider, valueLabel: valueLabel))
            lastAnchor = row.bottomAnchor
        }

        // Buttons
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelBtn.keyEquivalent = "\u{1b}" // Escape
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(cancelBtn)

        let applyBtn = NSButton(title: "Apply", target: self, action: #selector(applyTapped))
        applyBtn.keyEquivalent = "\r" // Return
        applyBtn.bezelStyle = .rounded
        applyBtn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(applyBtn)

        NSLayoutConstraint.activate([
            applyBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            applyBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            cancelBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            cancelBtn.trailingAnchor.constraint(equalTo: applyBtn.leadingAnchor, constant: -12),
        ])

        // Trigger initial preview with default values
        sendPreview()
    }

    // MARK: - Sheet Presentation

    func presentAsSheet(on window: NSWindow) {
        let params = filterType.parameters
        let height = CGFloat(60 + params.count * 40 + 60)
        preferredContentSize = NSSize(width: 360, height: height)
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
        let params = filterType.parameters
        for (i, (_, slider, valueLabel)) in sliders.enumerated() {
            if slider === sender, i < params.count {
                valueLabel.stringValue = formatValue(slider.doubleValue, param: params[i])
                break
            }
        }
        sendPreview()
    }

    @objc private func cancelTapped() {
        delegate?.filterSheetDidCancel()
        dismiss(nil)
    }

    @objc private func applyTapped() {
        delegate?.filterSheetDidApply(filterType, params: currentParams())
        dismiss(nil)
    }

    // MARK: - Helpers

    private func currentParams() -> [String: Double] {
        var params: [String: Double] = [:]
        for (key, slider, _) in sliders {
            params[key] = slider.doubleValue
        }
        return params
    }

    private func sendPreview() {
        delegate?.filterSheetDidChangeParams(filterType, params: currentParams())
    }

    private func formatValue(_ value: Double, param: FilterParam) -> String {
        if param.min == param.min.rounded() && param.max == param.max.rounded()
            && param.defaultValue == param.defaultValue.rounded() {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}
