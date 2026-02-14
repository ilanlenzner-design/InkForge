import AppKit

protocol AISheetDelegate: AnyObject {
    func aiSheetDidProduceImage(_ image: CGImage, mode: AIMode)
    func aiSheetDidProduceText(_ text: String)
    func aiSheetRequestsCanvasImage() -> CGImage?
    func aiSheetRequestsSelectionMask() -> CGImage?
    func aiSheetRequestsCanvasSize() -> CGSize
}

final class AISheetController: NSViewController {

    weak var delegate: AISheetDelegate?

    private var modePopup: NSPopUpButton!
    private var providerPopup: NSPopUpButton!
    private var promptLabel: NSTextField!
    private var promptField: NSTextField!
    private var infoLabel: NSTextField!
    private var progressBar: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var applyBtn: NSButton!
    private var cancelBtn: NSButton!
    private var settingsBtn: NSButton!

    private var isProcessing = false
    private var currentProvider: AIProvider?

    /// Flat list of modes in popup order (excludes group headers / separators).
    private var popupModes: [AIMode] = []

    private var selectedMode: AIMode {
        guard let item = modePopup.selectedItem, item.tag >= 0, item.tag < popupModes.count else {
            return .generate
        }
        return popupModes[item.tag]
    }

    override func loadView() {
        let width: CGFloat = 440
        let height: CGFloat = 380

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

        // Mode row
        let modeLabel = NSTextField(labelWithString: "Mode:")
        modeLabel.font = .systemFont(ofSize: 12)
        modeLabel.textColor = .inkTextDim
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(modeLabel)

        modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        modePopup.target = self
        modePopup.action = #selector(modeChanged)
        modePopup.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(modePopup)

        // Provider row
        let providerLabel = NSTextField(labelWithString: "Provider:")
        providerLabel.font = .systemFont(ofSize: 12)
        providerLabel.textColor = .inkTextDim
        providerLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(providerLabel)

        providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        providerPopup.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(providerPopup)

        // Prompt field
        promptLabel = NSTextField(labelWithString: "Prompt:")
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

        // Info label
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

        let labelWidth: CGFloat = 60

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            // Mode row
            modeLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            modeLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            modeLabel.widthAnchor.constraint(equalToConstant: labelWidth),

            modePopup.centerYAnchor.constraint(equalTo: modeLabel.centerYAnchor),
            modePopup.leadingAnchor.constraint(equalTo: modeLabel.trailingAnchor, constant: 4),
            modePopup.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            // Provider row
            providerLabel.topAnchor.constraint(equalTo: modeLabel.bottomAnchor, constant: 10),
            providerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            providerLabel.widthAnchor.constraint(equalToConstant: labelWidth),

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
            infoLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

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

        buildModePopup()
        updateProviderPopup()
        updateModeUI()
    }

    private func buildModePopup() {
        popupModes.removeAll()
        let menu = NSMenu()

        for (index, (group, modes)) in AIMode.groupedModes.enumerated() {
            if index > 0 {
                menu.addItem(.separator())
            }

            let header = NSMenuItem(title: group, action: nil, keyEquivalent: "")
            header.isEnabled = false
            header.tag = -1
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.inkTextDim,
            ]
            header.attributedTitle = NSAttributedString(string: group.uppercased(), attributes: attrs)
            menu.addItem(header)

            for mode in modes {
                let item = NSMenuItem(title: mode.displayName, action: nil, keyEquivalent: "")
                item.tag = popupModes.count
                menu.addItem(item)
                popupModes.append(mode)
            }
        }

        modePopup.menu = menu

        // Select first enabled item
        if let first = menu.items.first(where: { $0.isEnabled && $0.tag >= 0 }) {
            modePopup.select(first)
        }
    }

    // MARK: - Sheet Presentation

    func presentAsSheet(on window: NSWindow) {
        preferredContentSize = NSSize(width: 440, height: 380)
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
        updateModeUI()
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
        let mode = selectedMode
        let prompt = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if mode.needsPrompt && prompt.isEmpty {
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
        let inputImage: CGImage? = mode.needsInputImage ? delegate?.aiSheetRequestsCanvasImage() : nil
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
                        self.delegate?.aiSheetDidProduceImage(image, mode: mode)
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

    private func updateModeUI() {
        let mode = selectedMode
        promptField.placeholderString = mode.promptPlaceholder

        // Disable prompt for modes that don't need it
        let needsPrompt = mode.needsPrompt
        promptField.isEnabled = needsPrompt
        promptLabel.textColor = needsPrompt ? .inkTextDim : .disabledControlTextColor
        if !needsPrompt {
            promptField.stringValue = ""
        }

        updateProviderPopup()
        updateInfoLabel()
    }

    private func updateProviderPopup() {
        let mode = selectedMode
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
        let mode = selectedMode

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
        } else if let hint = mode.infoHint {
            infoLabel.stringValue = hint
            infoLabel.textColor = .inkTextDim
            infoLabel.isHidden = false
        } else {
            infoLabel.isHidden = true
        }
    }

    private func setProcessingUI(_ processing: Bool) {
        promptField.isEnabled = !processing && selectedMode.needsPrompt
        modePopup.isEnabled = !processing
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
