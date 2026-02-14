import AppKit

protocol TextSheetDelegate: AnyObject {
    func textSheetDidApply(text: String, fontName: String, fontSize: CGFloat,
                           isBold: Bool, isItalic: Bool, color: NSColor)
    func textSheetDidCancel()
    func textSheetDidChangeParams(text: String, fontName: String, fontSize: CGFloat,
                                  isBold: Bool, isItalic: Bool, color: NSColor)
}

final class TextSheetController: NSViewController, NSTextViewDelegate {

    weak var delegate: TextSheetDelegate?
    private(set) var isReEditing: Bool = false
    private var pendingPrefill: TextContent?

    /// Set before presenting to provide the initial color (defaults to black).
    var initialColor: NSColor = .black

    private var titleLabel: NSTextField!
    private var textView: NSTextView!
    private var fontPopup: NSPopUpButton!
    private var sizeSlider: NSSlider!
    private var sizeLabel: NSTextField!
    private var boldCheck: NSButton!
    private var italicCheck: NSButton!
    private var colorWell: NSColorWell!

    private let fontNames = [
        "Helvetica", "Arial", "Times New Roman", "Georgia",
        "Courier New", "Menlo", "American Typewriter", "Avenir",
        "Futura", "Gill Sans", "Optima", "Palatino", "Verdana",
    ]

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let width: CGFloat = 400
        let height: CGFloat = 400

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.inkPanel.cgColor
        self.view = container

        // Title
        titleLabel = NSTextField(labelWithString: isReEditing ? "Edit Text" : "Add Text")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .inkText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        // Text input (NSTextView in NSScrollView)
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        container.addSubview(scrollView)

        textView = NSTextView()
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .inkText
        textView.backgroundColor = NSColor.inkBg.withAlphaComponent(0.5)
        textView.isEditable = true
        textView.isSelectable = true
        textView.delegate = self
        textView.textContainerInset = NSSize(width: 4, height: 4)
        scrollView.documentView = textView

        // Font popup
        let fontLabel = NSTextField(labelWithString: "Font")
        fontLabel.font = .systemFont(ofSize: 13)
        fontLabel.textColor = .inkTextDim
        fontLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(fontLabel)

        fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        fontPopup.translatesAutoresizingMaskIntoConstraints = false
        for name in fontNames {
            fontPopup.addItem(withTitle: name)
        }
        fontPopup.target = self
        fontPopup.action = #selector(paramChanged)
        container.addSubview(fontPopup)

        // Size slider
        let sizeTextLabel = NSTextField(labelWithString: "Size")
        sizeTextLabel.font = .systemFont(ofSize: 13)
        sizeTextLabel.textColor = .inkTextDim
        sizeTextLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sizeTextLabel)

        sizeSlider = NSSlider(value: 24, minValue: 8, maxValue: 144,
                               target: self, action: #selector(sizeSliderChanged))
        sizeSlider.isContinuous = true
        sizeSlider.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sizeSlider)

        sizeLabel = NSTextField(labelWithString: "24")
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        sizeLabel.textColor = .inkText
        sizeLabel.alignment = .right
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sizeLabel)

        // Bold / Italic checkboxes
        boldCheck = NSButton(checkboxWithTitle: "Bold", target: self, action: #selector(paramChanged))
        boldCheck.translatesAutoresizingMaskIntoConstraints = false
        boldCheck.contentTintColor = .inkText
        container.addSubview(boldCheck)

        italicCheck = NSButton(checkboxWithTitle: "Italic", target: self, action: #selector(paramChanged))
        italicCheck.translatesAutoresizingMaskIntoConstraints = false
        italicCheck.contentTintColor = .inkText
        container.addSubview(italicCheck)

        // Color well
        let colorLabel = NSTextField(labelWithString: "Color")
        colorLabel.font = .systemFont(ofSize: 13)
        colorLabel.textColor = .inkTextDim
        colorLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(colorLabel)

        colorWell = NSColorWell(frame: .zero)
        colorWell.color = initialColor
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(colorWell)

        // Buttons
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelBtn.keyEquivalent = "\u{1b}"
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(cancelBtn)

        let applyBtn = NSButton(title: "Apply", target: self, action: #selector(applyTapped))
        applyBtn.keyEquivalent = "\r"
        applyBtn.bezelStyle = .rounded
        applyBtn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(applyBtn)

        NSLayoutConstraint.activate([
            // Title
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            // Text view
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            scrollView.heightAnchor.constraint(equalToConstant: 100),

            // Font row
            fontLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 16),
            fontLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            fontLabel.widthAnchor.constraint(equalToConstant: 40),
            fontPopup.centerYAnchor.constraint(equalTo: fontLabel.centerYAnchor),
            fontPopup.leadingAnchor.constraint(equalTo: fontLabel.trailingAnchor, constant: 8),
            fontPopup.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            // Size row
            sizeTextLabel.topAnchor.constraint(equalTo: fontLabel.bottomAnchor, constant: 16),
            sizeTextLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            sizeTextLabel.widthAnchor.constraint(equalToConstant: 40),
            sizeSlider.centerYAnchor.constraint(equalTo: sizeTextLabel.centerYAnchor),
            sizeSlider.leadingAnchor.constraint(equalTo: sizeTextLabel.trailingAnchor, constant: 8),
            sizeSlider.trailingAnchor.constraint(equalTo: sizeLabel.leadingAnchor, constant: -8),
            sizeLabel.centerYAnchor.constraint(equalTo: sizeTextLabel.centerYAnchor),
            sizeLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            sizeLabel.widthAnchor.constraint(equalToConstant: 40),

            // Style checkboxes
            boldCheck.topAnchor.constraint(equalTo: sizeTextLabel.bottomAnchor, constant: 16),
            boldCheck.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 60),
            italicCheck.centerYAnchor.constraint(equalTo: boldCheck.centerYAnchor),
            italicCheck.leadingAnchor.constraint(equalTo: boldCheck.trailingAnchor, constant: 20),

            // Color row
            colorLabel.topAnchor.constraint(equalTo: boldCheck.bottomAnchor, constant: 16),
            colorLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            colorLabel.widthAnchor.constraint(equalToConstant: 40),
            colorWell.centerYAnchor.constraint(equalTo: colorLabel.centerYAnchor),
            colorWell.leadingAnchor.constraint(equalTo: colorLabel.trailingAnchor, constant: 8),
            colorWell.widthAnchor.constraint(equalToConstant: 44),
            colorWell.heightAnchor.constraint(equalToConstant: 28),

            // Buttons
            applyBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            applyBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            cancelBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            cancelBtn.trailingAnchor.constraint(equalTo: applyBtn.leadingAnchor, constant: -12),
        ])

        // Pre-fill controls for re-edit, then focus text view
        DispatchQueue.main.async { [weak self] in
            self?.applyPrefill()
            self?.view.window?.makeFirstResponder(self?.textView)
        }
    }

    private func applyPrefill() {
        guard let content = pendingPrefill else { return }
        pendingPrefill = nil

        textView.string = content.text

        // Select matching font in popup
        if let idx = fontNames.firstIndex(of: content.fontName) {
            fontPopup.selectItem(at: idx)
        }

        sizeSlider.doubleValue = Double(content.fontSize)
        sizeLabel.stringValue = "\(Int(content.fontSize))"
        boldCheck.state = content.isBold ? .on : .off
        italicCheck.state = content.isItalic ? .on : .off
        colorWell.color = content.color

        sendPreview()
    }

    // MARK: - Re-edit Configuration

    /// Call BEFORE presenting the sheet to pre-fill controls for re-editing.
    func configureForReEdit(content: TextContent) {
        isReEditing = true
        pendingPrefill = content
    }

    // MARK: - Sheet Presentation

    func presentAsSheet(on window: NSWindow) {
        preferredContentSize = NSSize(width: 400, height: 400)
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

    @objc private func sizeSliderChanged() {
        sizeLabel.stringValue = "\(Int(sizeSlider.doubleValue))"
        sendPreview()
    }

    @objc private func paramChanged() {
        sendPreview()
    }

    @objc private func colorChanged() {
        sendPreview()
    }

    @objc private func cancelTapped() {
        delegate?.textSheetDidCancel()
        dismiss(nil)
    }

    @objc private func applyTapped() {
        let text = textView.string
        guard !text.isEmpty else {
            delegate?.textSheetDidCancel()
            dismiss(nil)
            return
        }
        delegate?.textSheetDidApply(
            text: text,
            fontName: fontPopup.titleOfSelectedItem ?? "Helvetica",
            fontSize: CGFloat(sizeSlider.doubleValue),
            isBold: boldCheck.state == .on,
            isItalic: italicCheck.state == .on,
            color: colorWell.color
        )
        dismiss(nil)
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        sendPreview()
    }

    // MARK: - Helpers

    private func sendPreview() {
        delegate?.textSheetDidChangeParams(
            text: textView.string,
            fontName: fontPopup.titleOfSelectedItem ?? "Helvetica",
            fontSize: CGFloat(sizeSlider.doubleValue),
            isBold: boldCheck.state == .on,
            isItalic: italicCheck.state == .on,
            color: colorWell.color
        )
    }
}
