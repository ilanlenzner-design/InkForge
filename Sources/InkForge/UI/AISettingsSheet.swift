import AppKit

protocol AISettingsSheetDelegate: AnyObject {
    func aiSettingsDidSave()
}

final class AISettingsSheet: NSViewController {

    weak var delegate: AISettingsSheetDelegate?

    private var geminiField: NSSecureTextField!
    private var replicateField: NSSecureTextField!

    override func loadView() {
        let width: CGFloat = 380
        let height: CGFloat = 210

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.inkPanel.cgColor
        self.view = container

        // Title
        let title = NSTextField(labelWithString: "AI Settings")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = .inkText
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)

        // Gemini row
        let geminiLabel = NSTextField(labelWithString: "Gemini API Key")
        geminiLabel.font = .systemFont(ofSize: 13)
        geminiLabel.textColor = .inkTextDim
        geminiLabel.alignment = .right
        geminiLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(geminiLabel)

        geminiField = NSSecureTextField()
        geminiField.placeholderString = "Enter Gemini API key..."
        geminiField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        geminiField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(geminiField)

        // Replicate row
        let replicateLabel = NSTextField(labelWithString: "Replicate API Key")
        replicateLabel.font = .systemFont(ofSize: 13)
        replicateLabel.textColor = .inkTextDim
        replicateLabel.alignment = .right
        replicateLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(replicateLabel)

        replicateField = NSSecureTextField()
        replicateField.placeholderString = "Enter Replicate API key..."
        replicateField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        replicateField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(replicateField)

        // Buttons
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelBtn.keyEquivalent = "\u{1b}"
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(cancelBtn)

        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        saveBtn.keyEquivalent = "\r"
        saveBtn.bezelStyle = .rounded
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(saveBtn)

        let labelWidth: CGFloat = 120

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            // Gemini row
            geminiLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 20),
            geminiLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            geminiLabel.widthAnchor.constraint(equalToConstant: labelWidth),

            geminiField.centerYAnchor.constraint(equalTo: geminiLabel.centerYAnchor),
            geminiField.leadingAnchor.constraint(equalTo: geminiLabel.trailingAnchor, constant: 8),
            geminiField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            // Replicate row
            replicateLabel.topAnchor.constraint(equalTo: geminiLabel.bottomAnchor, constant: 16),
            replicateLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            replicateLabel.widthAnchor.constraint(equalToConstant: labelWidth),

            replicateField.centerYAnchor.constraint(equalTo: replicateLabel.centerYAnchor),
            replicateField.leadingAnchor.constraint(equalTo: replicateLabel.trailingAnchor, constant: 8),
            replicateField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            // Buttons
            saveBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            saveBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            cancelBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            cancelBtn.trailingAnchor.constraint(equalTo: saveBtn.leadingAnchor, constant: -12),
        ])

        // Load existing keys
        let manager = AIProviderManager.shared
        geminiField.stringValue = manager.apiKey(for: "Gemini") ?? ""
        replicateField.stringValue = manager.apiKey(for: "Replicate") ?? ""
    }

    // MARK: - Sheet Presentation

    func presentAsSheet(on window: NSWindow) {
        preferredContentSize = NSSize(width: 380, height: 210)
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

    @objc private func cancelTapped() {
        dismiss(nil)
    }

    @objc private func saveTapped() {
        let manager = AIProviderManager.shared
        manager.setAPIKey(geminiField.stringValue.trimmingCharacters(in: .whitespaces), for: "Gemini")
        manager.setAPIKey(replicateField.stringValue.trimmingCharacters(in: .whitespaces), for: "Replicate")
        delegate?.aiSettingsDidSave()
        dismiss(nil)
    }
}
