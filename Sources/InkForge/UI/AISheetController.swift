import AppKit

protocol AISheetDelegate: AnyObject {
    func aiSheetDidProduceImage(_ image: CGImage)
    func aiSheetDidProduceText(_ text: String)
    func aiSheetRequestsCanvasImage() -> CGImage?
    func aiSheetRequestsSelectionMask() -> CGImage?
    func aiSheetRequestsCanvasSize() -> CGSize
}

final class AISheetController: NSViewController {

    weak var delegate: AISheetDelegate?

    private var modeSegment: NSSegmentedControl!
    private var providerPopup: NSPopUpButton!
    private var promptField: NSTextField!
    private var infoLabel: NSTextField!
    private var progressBar: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var applyBtn: NSButton!
    private var cancelBtn: NSButton!
    private var settingsBtn: NSButton!

    private var isProcessing = false
    private var currentProvider: AIProvider?

    private let modes = AIMode.allCases

    override func loadView() {
        let width: CGFloat = 440
        let height: CGFloat = 360

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.inkPanel.cgColor
        self.view = container

        // Title
        let title = NSTextField(labelWithString: "AI Edit")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = .inkText
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)

        // Mode segment
        let modeLabels = modes.map { $0.displayName }
        modeSegment = NSSegmentedControl(labels: modeLabels, trackingMode: .selectOne,
                                          target: self, action: #selector(modeChanged))
        modeSegment.selectedSegment = 0
        modeSegment.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(modeSegment)

        // Provider popup
        let providerLabel = NSTextField(labelWithString: "Provider:")
        providerLabel.font = .systemFont(ofSize: 12)
        providerLabel.textColor = .inkTextDim
        providerLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(providerLabel)

        providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        providerPopup.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(providerPopup)

        // Prompt field
        let promptLabel = NSTextField(labelWithString: "Prompt:")
        promptLabel.font = .systemFont(ofSize: 12)
        promptLabel.textColor = .inkTextDim
        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(promptLabel)

        promptField = NSTextField()
        promptField.placeholderString = AIMode.generate.promptPlaceholder
        promptField.font = .systemFont(ofSize: 13)
        promptField.lineBreakMode = .byWordWrapping
        promptField.usesSingleLineMode = false
        promptField.cell?.wraps = true
        promptField.cell?.isScrollable = false
        promptField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(promptField)

        // Info label (for inpaint mode)
        infoLabel = NSTextField(labelWithString: "")
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.textColor = .inkAccent
        infoLabel.isHidden = true
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(infoLabel)

        // Progress bar
        progressBar = NSProgressIndicator()
        progressBar.style = .bar
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.isIndeterminate = false
        progressBar.isHidden = true
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(progressBar)

        // Status label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .inkTextDim
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(statusLabel)

        // Buttons
        cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelBtn.keyEquivalent = "\u{1b}"
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(cancelBtn)

        settingsBtn = NSButton(title: "Settings...", target: self, action: #selector(settingsTapped))
        settingsBtn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(settingsBtn)

        applyBtn = NSButton(title: "Apply", target: self, action: #selector(applyTapped))
        applyBtn.keyEquivalent = "\r"
        applyBtn.bezelStyle = .rounded
        applyBtn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(applyBtn)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            // Mode segment
            modeSegment.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            modeSegment.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            modeSegment.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            // Provider row
            providerLabel.topAnchor.constraint(equalTo: modeSegment.bottomAnchor, constant: 14),
            providerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            providerLabel.widthAnchor.constraint(equalToConstant: 60),

            providerPopup.centerYAnchor.constraint(equalTo: providerLabel.centerYAnchor),
            providerPopup.leadingAnchor.constraint(equalTo: providerLabel.trailingAnchor, constant: 4),
            providerPopup.widthAnchor.constraint(equalToConstant: 180),

            // Prompt
            promptLabel.topAnchor.constraint(equalTo: providerLabel.bottomAnchor, constant: 14),
            promptLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            promptField.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 4),
            promptField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            promptField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            promptField.heightAnchor.constraint(equalToConstant: 60),

            // Info label
            infoLabel.topAnchor.constraint(equalTo: promptField.bottomAnchor, constant: 6),
            infoLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            // Progress bar
            progressBar.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 10),
            progressBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            progressBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            // Status label
            statusLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            // Buttons
            applyBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            applyBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            cancelBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            cancelBtn.trailingAnchor.constraint(equalTo: applyBtn.leadingAnchor, constant: -12),
            settingsBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            settingsBtn.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
        ])

        updateProviderPopup()
        updateInfoLabel()
    }

    // MARK: - Sheet Presentation

    func presentAsSheet(on window: NSWindow) {
        preferredContentSize = NSSize(width: 440, height: 360)
        let sheetWindow = NSWindow(contentViewController: self)
        sheetWindow.styleMask = [.titled]
        window.beginSheet(sheetWindow, completionHandler: nil)
    }

    override func dismiss(_ sender: Any?) {
        if isProcessing {
            currentProvider?.cancel()
            isProcessing = false
        }
        if let sheetWindow = view.window, let parent = sheetWindow.sheetParent {
            parent.endSheet(sheetWindow)
        } else {
            super.dismiss(sender)
        }
    }

    // MARK: - Actions

    @objc private func modeChanged() {
        let mode = modes[modeSegment.selectedSegment]
        promptField.placeholderString = mode.promptPlaceholder
        updateProviderPopup()
        updateInfoLabel()
    }

    @objc private func cancelTapped() {
        if isProcessing {
            currentProvider?.cancel()
            resetUI()
            setStatus("Cancelled.", isError: false)
        } else {
            dismiss(nil)
        }
    }

    @objc private func settingsTapped() {
        guard let window = view.window ?? view.window?.sheetParent else { return }
        let settings = AISettingsSheet()
        settings.delegate = self
        settings.presentAsSheet(on: window)
    }

    @objc private func applyTapped() {
        let mode = modes[modeSegment.selectedSegment]
        let prompt = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if prompt.isEmpty {
            setStatus("Please enter a prompt.", isError: true)
            return
        }

        // Get the selected provider
        guard let providerIndex = providerPopup.indexOfSelectedItem as Int?,
              providerIndex >= 0 else {
            setStatus("No provider available. Check Settings.", isError: true)
            return
        }

        let availableProviders = AIProviderManager.shared.allProviders(for: mode)
        guard providerIndex < availableProviders.count else {
            setStatus("No provider configured for this mode. Check Settings.", isError: true)
            return
        }

        let provider = availableProviders[providerIndex]

        // Build request
        let canvasSize = delegate?.aiSheetRequestsCanvasSize() ?? CGSize(width: 1024, height: 1024)
        let inputImage: CGImage? = (mode != .generate) ? delegate?.aiSheetRequestsCanvasImage() : nil
        let maskImage: CGImage? = (mode == .inpaint) ? delegate?.aiSheetRequestsSelectionMask() : nil

        let request = AIRequest(
            mode: mode,
            prompt: prompt,
            inputImage: inputImage,
            maskImage: maskImage,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height)
        )

        // Start processing
        isProcessing = true
        currentProvider = provider
        setProcessingUI(true)
        setStatus("Sending to \(provider.name)...", isError: false)

        provider.process(request, progress: { [weak self] value in
            DispatchQueue.main.async {
                self?.progressBar.doubleValue = value
                if value > 0.1 && value < 0.9 {
                    self?.setStatus("Processing...", isError: false)
                }
            }
        }, completion: { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isProcessing = false
                self.currentProvider = nil

                switch result {
                case .success(let response):
                    if let image = response.resultImage {
                        self.delegate?.aiSheetDidProduceImage(image)
                        self.dismiss(nil)
                    } else if let text = response.text {
                        self.delegate?.aiSheetDidProduceText(text)
                        self.dismiss(nil)
                    } else {
                        self.resetUI()
                        self.setStatus("No result returned.", isError: true)
                    }

                case .failure(let error):
                    self.resetUI()
                    self.setStatus(error.localizedDescription, isError: true)
                }
            }
        })
    }

    // MARK: - UI Helpers

    private func updateProviderPopup() {
        let mode = modes[modeSegment.selectedSegment]
        let available = AIProviderManager.shared.allProviders(for: mode)

        providerPopup.removeAllItems()
        if available.isEmpty {
            providerPopup.addItem(withTitle: "No providers configured")
            providerPopup.isEnabled = false
        } else {
            for provider in available {
                providerPopup.addItem(withTitle: provider.name)
            }
            providerPopup.isEnabled = true
        }
    }

    private func updateInfoLabel() {
        let mode = modes[modeSegment.selectedSegment]
        if mode == .inpaint {
            let hasMask = delegate?.aiSheetRequestsSelectionMask() != nil
            if hasMask {
                infoLabel.stringValue = "Active selection will be used as inpaint mask."
                infoLabel.textColor = .inkAccent
            } else {
                infoLabel.stringValue = "No selection active — entire image will be sent."
                infoLabel.textColor = .inkTextDim
            }
            infoLabel.isHidden = false
        } else if mode == .generate {
            infoLabel.stringValue = "A new layer will be created with the generated image."
            infoLabel.textColor = .inkTextDim
            infoLabel.isHidden = false
        } else {
            infoLabel.isHidden = true
        }
    }

    private func setProcessingUI(_ processing: Bool) {
        promptField.isEnabled = !processing
        modeSegment.isEnabled = !processing
        providerPopup.isEnabled = !processing
        applyBtn.isEnabled = !processing
        settingsBtn.isEnabled = !processing
        progressBar.isHidden = !processing
        statusLabel.isHidden = false

        if processing {
            progressBar.doubleValue = 0
            cancelBtn.title = "Stop"
        } else {
            cancelBtn.title = "Cancel"
        }
    }

    private func resetUI() {
        setProcessingUI(false)
        updateProviderPopup()
    }

    private func setStatus(_ text: String, isError: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? NSColor.systemRed : .inkTextDim
        statusLabel.isHidden = false
    }
}

// MARK: - AISettingsSheetDelegate

extension AISheetController: AISettingsSheetDelegate {
    func aiSettingsDidSave() {
        updateProviderPopup()
    }
}
