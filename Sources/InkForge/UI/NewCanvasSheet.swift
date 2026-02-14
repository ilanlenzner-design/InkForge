import AppKit

// MARK: - Delegate Protocol

protocol NewCanvasSheetDelegate: AnyObject {
    func newCanvasSheet(_ sheet: NewCanvasSheet, didCreateWithSize size: CGSize, backgroundColor: NSColor)
}

// MARK: - Canvas Preset

private struct CanvasPreset {
    let name: String
    let width: Int?
    let height: Int?
    let dpi: Int?

    static let all: [CanvasPreset] = [
        CanvasPreset(name: "Custom",              width: nil,  height: nil,  dpi: nil),
        CanvasPreset(name: "1920\u{00D7}1080 (HD)",  width: 1920, height: 1080, dpi: 72),
        CanvasPreset(name: "2048\u{00D7}2048",       width: 2048, height: 2048, dpi: 150),
        CanvasPreset(name: "3000\u{00D7}3000",       width: 3000, height: 3000, dpi: 150),
        CanvasPreset(name: "4096\u{00D7}4096",       width: 4096, height: 4096, dpi: 150),
        CanvasPreset(name: "A4 300dpi (2480\u{00D7}3508)", width: 2480, height: 3508, dpi: 300),
    ]
}

// MARK: - NewCanvasSheet

final class NewCanvasSheet: NSViewController {

    // MARK: Delegate

    weak var delegate: NewCanvasSheetDelegate?

    // MARK: Constants

    private static let dpiOptions: [Int] = [72, 150, 300]
    private static let defaultDPIIndex = 1          // 150
    private static let defaultWidth = 2048
    private static let defaultHeight = 2048
    private static let minDimension: Double = 64
    private static let maxDimension: Double = 8192

    private enum Background: Int, CaseIterable {
        case white = 0
        case black
        case transparent

        var title: String {
            switch self {
            case .white:       return "White"
            case .black:       return "Black"
            case .transparent: return "Transparent"
            }
        }

        var color: NSColor {
            switch self {
            case .white:       return .white
            case .black:       return .black
            case .transparent: return .clear
            }
        }
    }

    // MARK: Controls

    private let presetPopUp   = NSPopUpButton(frame: .zero, pullsDown: false)
    private let widthField    = NSTextField()
    private let widthStepper  = NSStepper()
    private let heightField   = NSTextField()
    private let heightStepper = NSStepper()
    private let dpiPopUp      = NSPopUpButton(frame: .zero, pullsDown: false)
    private let bgPopUp       = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cancelButton  = NSButton(title: "Cancel", target: nil, action: nil)
    private let createButton  = NSButton(title: "Create", target: nil, action: nil)

    // MARK: Lifecycle

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 300))
        self.view = container
        buildUI(in: container)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "New Canvas"
        applyDefaults()
    }

    // MARK: - UI Construction

    private func buildUI(in container: NSView) {
        // --- Labels ---
        let presetLabel = makeLabel("Preset:")
        let widthLabel  = makeLabel("Width:")
        let heightLabel = makeLabel("Height:")
        let dpiLabel    = makeLabel("DPI:")
        let bgLabel     = makeLabel("Background:")

        // --- Preset popup ---
        for preset in CanvasPreset.all {
            presetPopUp.addItem(withTitle: preset.name)
        }
        presetPopUp.target = self
        presetPopUp.action = #selector(presetChanged(_:))

        // --- Width ---
        configureDimensionField(widthField)
        configureDimensionStepper(widthStepper, action: #selector(widthStepperChanged(_:)))

        // --- Height ---
        configureDimensionField(heightField)
        configureDimensionStepper(heightStepper, action: #selector(heightStepperChanged(_:)))

        // --- DPI popup ---
        for dpi in Self.dpiOptions {
            dpiPopUp.addItem(withTitle: "\(dpi)")
        }

        // --- Background popup ---
        for bg in Background.allCases {
            bgPopUp.addItem(withTitle: bg.title)
        }

        // --- Buttons ---
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped(_:))
        cancelButton.keyEquivalent = "\u{1b}" // Escape

        createButton.target = self
        createButton.action = #selector(createTapped(_:))
        createButton.keyEquivalent = "\r"     // Return
        createButton.bezelStyle = .rounded
        if #available(macOS 11.0, *) {
            createButton.hasDestructiveAction = false
        }

        // --- Layout with Auto Layout ---
        let allViews: [NSView] = [
            presetLabel, presetPopUp,
            widthLabel, widthField, widthStepper,
            heightLabel, heightField, heightStepper,
            dpiLabel, dpiPopUp,
            bgLabel, bgPopUp,
            cancelButton, createButton,
        ]
        for v in allViews {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }

        // Separator line above buttons
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator)

        let padding: CGFloat = 20
        let rowHeight: CGFloat = 26
        let fieldWidth: CGFloat = 90
        let labelWidth: CGFloat = 90
        let popUpWidth: CGFloat = 190

        NSLayoutConstraint.activate([
            // -- Row 1: Preset --
            presetLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            presetLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            presetLabel.widthAnchor.constraint(equalToConstant: labelWidth),
            presetLabel.heightAnchor.constraint(equalToConstant: rowHeight),

            presetPopUp.centerYAnchor.constraint(equalTo: presetLabel.centerYAnchor),
            presetPopUp.leadingAnchor.constraint(equalTo: presetLabel.trailingAnchor, constant: 8),
            presetPopUp.widthAnchor.constraint(equalToConstant: popUpWidth),

            // -- Row 2: Width --
            widthLabel.topAnchor.constraint(equalTo: presetLabel.bottomAnchor, constant: 12),
            widthLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            widthLabel.widthAnchor.constraint(equalToConstant: labelWidth),
            widthLabel.heightAnchor.constraint(equalToConstant: rowHeight),

            widthField.centerYAnchor.constraint(equalTo: widthLabel.centerYAnchor),
            widthField.leadingAnchor.constraint(equalTo: widthLabel.trailingAnchor, constant: 8),
            widthField.widthAnchor.constraint(equalToConstant: fieldWidth),
            widthField.heightAnchor.constraint(equalToConstant: 22),

            widthStepper.centerYAnchor.constraint(equalTo: widthLabel.centerYAnchor),
            widthStepper.leadingAnchor.constraint(equalTo: widthField.trailingAnchor, constant: 4),

            // -- Row 3: Height --
            heightLabel.topAnchor.constraint(equalTo: widthLabel.bottomAnchor, constant: 12),
            heightLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            heightLabel.widthAnchor.constraint(equalToConstant: labelWidth),
            heightLabel.heightAnchor.constraint(equalToConstant: rowHeight),

            heightField.centerYAnchor.constraint(equalTo: heightLabel.centerYAnchor),
            heightField.leadingAnchor.constraint(equalTo: heightLabel.trailingAnchor, constant: 8),
            heightField.widthAnchor.constraint(equalToConstant: fieldWidth),
            heightField.heightAnchor.constraint(equalToConstant: 22),

            heightStepper.centerYAnchor.constraint(equalTo: heightLabel.centerYAnchor),
            heightStepper.leadingAnchor.constraint(equalTo: heightField.trailingAnchor, constant: 4),

            // -- Row 4: DPI --
            dpiLabel.topAnchor.constraint(equalTo: heightLabel.bottomAnchor, constant: 12),
            dpiLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            dpiLabel.widthAnchor.constraint(equalToConstant: labelWidth),
            dpiLabel.heightAnchor.constraint(equalToConstant: rowHeight),

            dpiPopUp.centerYAnchor.constraint(equalTo: dpiLabel.centerYAnchor),
            dpiPopUp.leadingAnchor.constraint(equalTo: dpiLabel.trailingAnchor, constant: 8),
            dpiPopUp.widthAnchor.constraint(equalToConstant: popUpWidth),

            // -- Row 5: Background --
            bgLabel.topAnchor.constraint(equalTo: dpiLabel.bottomAnchor, constant: 12),
            bgLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            bgLabel.widthAnchor.constraint(equalToConstant: labelWidth),
            bgLabel.heightAnchor.constraint(equalToConstant: rowHeight),

            bgPopUp.centerYAnchor.constraint(equalTo: bgLabel.centerYAnchor),
            bgPopUp.leadingAnchor.constraint(equalTo: bgLabel.trailingAnchor, constant: 8),
            bgPopUp.widthAnchor.constraint(equalToConstant: popUpWidth),

            // -- Separator --
            separator.topAnchor.constraint(equalTo: bgLabel.bottomAnchor, constant: 16),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),

            // -- Buttons --
            createButton.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 12),
            createButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            createButton.widthAnchor.constraint(equalToConstant: 80),

            cancelButton.centerYAnchor.constraint(equalTo: createButton.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: createButton.leadingAnchor, constant: -8),
            cancelButton.widthAnchor.constraint(equalToConstant: 80),

            createButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
        ])
    }

    // MARK: - Defaults

    private func applyDefaults() {
        widthField.integerValue = Self.defaultWidth
        widthStepper.integerValue = Self.defaultWidth
        heightField.integerValue = Self.defaultHeight
        heightStepper.integerValue = Self.defaultHeight
        dpiPopUp.selectItem(at: Self.defaultDPIIndex)
        bgPopUp.selectItem(at: 0)
        presetPopUp.selectItem(at: 0) // Custom
    }

    // MARK: - Helpers

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.font = .systemFont(ofSize: 13)
        return label
    }

    private func configureDimensionField(_ field: NSTextField) {
        field.formatter = dimensionFormatter()
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.alignment = .right
        field.delegate = self
    }

    private func configureDimensionStepper(_ stepper: NSStepper, action: Selector) {
        stepper.minValue = Self.minDimension
        stepper.maxValue = Self.maxDimension
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = action
    }

    private func dimensionFormatter() -> NumberFormatter {
        let fmt = NumberFormatter()
        fmt.numberStyle = .none
        fmt.minimum = NSNumber(value: Self.minDimension)
        fmt.maximum = NSNumber(value: Self.maxDimension)
        fmt.allowsFloats = false
        return fmt
    }

    private func clampedDimension(_ value: Int) -> Int {
        min(max(value, Int(Self.minDimension)), Int(Self.maxDimension))
    }

    private func syncPresetToCustom() {
        presetPopUp.selectItem(at: 0) // "Custom"
    }

    // MARK: - Actions

    @objc private func widthStepperChanged(_ sender: NSStepper) {
        widthField.integerValue = sender.integerValue
        syncPresetToCustom()
    }

    @objc private func heightStepperChanged(_ sender: NSStepper) {
        heightField.integerValue = sender.integerValue
        syncPresetToCustom()
    }

    @objc private func presetChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index > 0 else { return } // "Custom" selected; do nothing

        let preset = CanvasPreset.all[index]
        if let w = preset.width {
            widthField.integerValue = w
            widthStepper.integerValue = w
        }
        if let h = preset.height {
            heightField.integerValue = h
            heightStepper.integerValue = h
        }
        if let dpi = preset.dpi, let dpiIndex = Self.dpiOptions.firstIndex(of: dpi) {
            dpiPopUp.selectItem(at: dpiIndex)
        }
    }

    @objc private func cancelTapped(_ sender: Any?) {
        dismiss(nil)
    }

    @objc private func createTapped(_ sender: Any?) {
        // Commit any in-progress field editing
        view.window?.makeFirstResponder(nil)

        let width  = CGFloat(clampedDimension(widthField.integerValue))
        let height = CGFloat(clampedDimension(heightField.integerValue))
        let size   = CGSize(width: width, height: height)

        let bgIndex = bgPopUp.indexOfSelectedItem
        let bgColor = Background(rawValue: bgIndex)?.color ?? .white

        delegate?.newCanvasSheet(self, didCreateWithSize: size, backgroundColor: bgColor)
        dismiss(nil)
    }

    // MARK: - Presentation Helper

    /// Present this sheet on a given window.
    func presentAsSheet(on window: NSWindow) {
        preferredContentSize = NSSize(width: 340, height: 300)
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
}

// MARK: - NSTextFieldDelegate

extension NewCanvasSheet: NSTextFieldDelegate {

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }

        let clamped = clampedDimension(field.integerValue)
        field.integerValue = clamped

        if field === widthField {
            widthStepper.integerValue = clamped
        } else if field === heightField {
            heightStepper.integerValue = clamped
        }

        syncPresetToCustom()
    }
}
