import AppKit
import UniformTypeIdentifiers
import ImageIO

class MainWindowController: NSWindowController {

    private(set) var canvasModel: CanvasModel
    let toolManager: ToolManager
    private(set) var exportManager: ExportManager

    let canvasView = CanvasView()
    let toolbarView = ToolbarView()
    let sidebarSliders = SidebarSlidersView()
    let layerPanel = LayerPanelView()
    var colorPickerSidebar: ColorPickerSidebarView!
    let statusBar = StatusBarView()
    let knobStrip = KnobStripView()

    private lazy var brushSettingsPopover = BrushSettingsPopover()
    private lazy var brushPickerPopover = BrushPickerPopover()

    private var canvasToPanel: NSLayoutConstraint!
    private var canvasToEdge: NSLayoutConstraint!
    private(set) var isLayerPanelVisible = true

    init(canvasModel: CanvasModel) {
        self.canvasModel = canvasModel
        self.toolManager = ToolManager()
        self.exportManager = ExportManager(canvasModel: canvasModel)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "InkForge"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .inkBg
        window.center()
        window.minSize = NSSize(width: 1000, height: 700)

        super.init(window: window)

        colorPickerSidebar = ColorPickerSidebarView()

        setupViews()
        setupBindings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    private func setupViews() {
        guard let window = window, let contentView = window.contentView else { return }

        canvasView.canvasModel = canvasModel
        canvasView.toolManager = toolManager
        canvasView.translatesAutoresizingMaskIntoConstraints = false

        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        sidebarSliders.translatesAutoresizingMaskIntoConstraints = false
        layerPanel.translatesAutoresizingMaskIntoConstraints = false
        colorPickerSidebar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        knobStrip.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(toolbarView)
        contentView.addSubview(sidebarSliders)
        contentView.addSubview(canvasView)
        contentView.addSubview(knobStrip)
        contentView.addSubview(layerPanel)
        contentView.addSubview(colorPickerSidebar)
        contentView.addSubview(statusBar)

        // Switchable constraints for layer panel toggle
        canvasToPanel = canvasView.trailingAnchor.constraint(equalTo: knobStrip.leadingAnchor)
        canvasToEdge = canvasView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        canvasToEdge.isActive = false

        NSLayoutConstraint.activate([
            // Toolbar at top
            toolbarView.topAnchor.constraint(equalTo: contentView.topAnchor),
            toolbarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: 52),

            // Status bar at bottom
            statusBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            statusBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 28),

            // Sidebar sliders on left
            sidebarSliders.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            sidebarSliders.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sidebarSliders.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            sidebarSliders.widthAnchor.constraint(equalToConstant: 56),

            // Knob strip on right, between canvas and layer panel
            knobStrip.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            knobStrip.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            knobStrip.trailingAnchor.constraint(equalTo: layerPanel.leadingAnchor),
            knobStrip.widthAnchor.constraint(equalToConstant: 170),

            // Layer panel on right (top portion)
            layerPanel.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            layerPanel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            layerPanel.bottomAnchor.constraint(equalTo: colorPickerSidebar.topAnchor),
            layerPanel.widthAnchor.constraint(equalToConstant: 240),

            // Color picker on right (bottom portion)
            colorPickerSidebar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            colorPickerSidebar.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            colorPickerSidebar.widthAnchor.constraint(equalToConstant: 240),
            colorPickerSidebar.heightAnchor.constraint(equalToConstant: 320),

            // Canvas between sidebar and knob strip
            canvasView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            canvasView.leadingAnchor.constraint(equalTo: sidebarSliders.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            canvasToPanel,
        ])

        layerPanel.layerStack = canvasModel.layerStack
    }

    private func setupBindings() {
        toolbarView.delegate = self
        sidebarSliders.delegate = self
        layerPanel.delegate = self
        colorPickerSidebar.delegate = self
        canvasModel.delegate = self
        canvasModel.layerStack.delegate = self
        toolManager.delegate = self
        toolManager.textTool.sheetDelegate = self
        brushSettingsPopover.settingsDelegate = self
        brushPickerPopover.pickerDelegate = self
        knobStrip.delegate = self

        // Status bar updates
        NotificationCenter.default.addObserver(self, selector: #selector(canvasTransformChanged),
                                               name: .canvasTransformChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(toolSettingsChanged),
                                               name: .toolSettingsChanged, object: nil)

        // Initial status
        statusBar.updateTool(toolManager.activeTool.name)
        statusBar.updateZoom(canvasView.canvasTransform.zoomPercentage)
        sidebarSliders.updateBrushSize(toolManager.currentBrushPreset.maxRadius)
        sidebarSliders.updateOpacity(toolManager.currentBrushPreset.opacity)
        knobStrip.updateZoom(canvasView.canvasTransform.scale)
        knobStrip.updateRotation(0)
        knobStrip.updateBrushSize(toolManager.currentBrushPreset.maxRadius)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        DispatchQueue.main.async { [weak self] in
            self?.canvasView.fitCanvasToView()
        }
    }

    // MARK: - Layer Panel Toggle

    func toggleLayerPanel() {
        isLayerPanelVisible.toggle()
        if isLayerPanelVisible {
            layerPanel.isHidden = false
            colorPickerSidebar.isHidden = false
            knobStrip.isHidden = false
            canvasToEdge.isActive = false
            canvasToPanel.isActive = true
        } else {
            canvasToPanel.isActive = false
            canvasToEdge.isActive = true
            layerPanel.isHidden = true
            colorPickerSidebar.isHidden = true
            knobStrip.isHidden = true
        }
        window?.contentView?.needsLayout = true
    }

    // MARK: - Export (called by AppDelegate menu)

    func exportImage(format: String) {
        guard let window = window else { return }
        switch format {
        case "png":  exportManager.exportImage(format: .png, from: window)
        case "jpeg": exportManager.exportImage(format: .jpeg(quality: 0.9), from: window)
        case "tiff": exportManager.exportImage(format: .tiff, from: window)
        default:     exportManager.exportImage(format: .png, from: window)
        }
    }

    // MARK: - New Canvas

    func showNewCanvasSheet() {
        guard let window = window else { return }
        let sheet = NewCanvasSheet()
        sheet.delegate = self
        sheet.presentAsSheet(on: window)
    }

    func rasterizeActiveTextLayer() {
        layerPanelDidRasterize(at: canvasModel.layerStack.activeLayerIndex)
    }

    @objc private func canvasTransformChanged() {
        let zoom = canvasView.canvasTransform.zoomPercentage
        statusBar.updateZoom(zoom)
        toolbarView.updateZoom(zoom)
        knobStrip.updateZoom(canvasView.canvasTransform.scale)
        knobStrip.updateRotation(canvasView.canvasTransform.rotation)
    }

    @objc private func toolSettingsChanged() {
        sidebarSliders.updateBrushSize(toolManager.currentBrushPreset.maxRadius)
        knobStrip.updateBrushSize(toolManager.currentBrushPreset.maxRadius)
    }
}

// MARK: - ToolbarViewDelegate

extension MainWindowController: ToolbarViewDelegate {
    func toolbarDidSelectTool(_ toolName: String) {
        // Auto-commit transform if switching away from it
        if let transform = toolManager.activeTool as? TransformTool, transform.isActive {
            transform.commit(canvas: canvasView)
        }

        switch toolName {
        case "Pen":
            toolManager.selectTool(toolManager.penTool)
            toolManager.currentBrushPreset = .defaultRound
        case "Pencil":
            toolManager.selectTool(toolManager.penTool)
            toolManager.currentBrushPreset = .defaultPencil
        case "Marker":
            toolManager.selectTool(toolManager.penTool)
            toolManager.currentBrushPreset = .defaultMarker
        case "Spray":
            toolManager.selectTool(toolManager.penTool)
            toolManager.currentBrushPreset = .defaultSpray
        case "Soft Round":
            toolManager.selectTool(toolManager.penTool)
            toolManager.currentBrushPreset = .defaultSoftRound
        case "Smudge":
            toolManager.selectTool(toolManager.smudgeTool)
        case "Eraser":
            toolManager.selectTool(toolManager.eraserTool)
        case "Fill":
            toolManager.selectTool(toolManager.fillTool)
        case "Select":
            toolManager.selectTool(toolManager.selectionTool)
        case "Transform":
            toolManager.selectTool(toolManager.transformTool)
        case "Pan":
            toolManager.selectTool(toolManager.panTool)
        case "Zoom":
            toolManager.selectTool(toolManager.zoomTool)
        case "Eyedropper":
            toolManager.selectTool(toolManager.eyedropperTool)
        case "Text":
            toolManager.selectTool(toolManager.textTool)
        default:
            break
        }
        statusBar.updateTool(toolManager.activeTool.name)
        window?.makeFirstResponder(canvasView)
    }

    func toolbarDidRequestBrushSettings(relativeTo view: NSView) {
        brushSettingsPopover.brushPreset = toolManager.currentBrushPreset
        brushSettingsPopover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }

    func toolbarDidRequestBrushPicker(relativeTo view: NSView) {
        brushPickerPopover.selectedPresetName = toolManager.currentBrushPreset.name
        brushPickerPopover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }

    func toolbarDidRequestColorPicker(relativeTo view: NSView) {
        // Color picker is always visible in sidebar — no popover needed
    }

    func toolbarDidToggleLayerPanel() {
        toggleLayerPanel()
    }

    func toolbarDidUndo() {
        canvasModel.undo()
    }

    func toolbarDidRedo() {
        canvasModel.redo()
    }

    func toolbarDidRequestNewCanvas() {
        showNewCanvasSheet()
    }

    func toolbarDidRequestExport(format: String) {
        exportImage(format: format)
    }

    func toolbarDidRequestImportImage() {
        importImageAsLayer()
    }

    func toolbarDidRequestOpenImageAsCanvas() {
        openImageAsCanvas()
    }

    func toolbarDidChangeZoom(_ percentage: Int) {
        let center = CGPoint(x: canvasView.bounds.midX, y: canvasView.bounds.midY)
        let newScale = CGFloat(percentage) / 100.0
        let canvasCenter = canvasView.canvasTransform.viewToCanvas(center)
        canvasView.canvasTransform.scale = newScale
        canvasView.canvasTransform.offset.x = center.x - canvasCenter.x * newScale
        canvasView.canvasTransform.offset.y = center.y - canvasCenter.y * newScale
        canvasView.needsDisplay = true
        statusBar.updateZoom(percentage)
    }

    func toolbarDidRequestFitToScreen() {
        canvasView.fitCanvasToView()
    }

    func toolbarDidRequestAI() {
        showAISheet()
    }
}

// MARK: - SidebarSlidersDelegate

extension MainWindowController: SidebarSlidersDelegate {
    func sidebarDidChangeBrushSize(_ size: CGFloat) {
        toolManager.currentBrushPreset.maxRadius = size
        canvasView.showBrushSizePreview(radius: size)
    }

    func sidebarDidChangeOpacity(_ opacity: CGFloat) {
        toolManager.currentBrushPreset.opacity = opacity
    }
}

// MARK: - BrushSettingsDelegate

extension MainWindowController: BrushSettingsDelegate {
    func brushSettingsDidChange(_ preset: BrushPreset) {
        toolManager.currentBrushPreset = preset
        sidebarSliders.updateBrushSize(preset.maxRadius)
        sidebarSliders.updateOpacity(preset.opacity)
    }
}

// MARK: - BrushPickerDelegate

extension MainWindowController: BrushPickerDelegate {
    func brushPickerDidSelectPreset(_ preset: BrushPreset) {
        toolManager.selectTool(toolManager.penTool)
        toolManager.currentBrushPreset = preset
        sidebarSliders.updateBrushSize(preset.maxRadius)
        sidebarSliders.updateOpacity(preset.opacity)
        knobStrip.updateBrushSize(preset.maxRadius)
        statusBar.updateTool(toolManager.activeTool.name)
        toolbarView.updateActiveTool(preset.name)
        window?.makeFirstResponder(canvasView)
    }
}

// MARK: - ColorPickerSidebarDelegate

extension MainWindowController: ColorPickerSidebarDelegate {
    func colorPickerSidebarDidSelectColor(_ color: NSColor) {
        toolManager.currentColor = color
    }
}

// MARK: - NewCanvasSheetDelegate

extension MainWindowController: NewCanvasSheetDelegate {
    func newCanvasSheet(_ sheet: NewCanvasSheet, didCreateWithSize size: CGSize, backgroundColor: NSColor) {
        let newModel = CanvasModel(size: size)
        if backgroundColor != .clear {
            newModel.layerStack.activeLayer?.fillWith(color: backgroundColor)
        }

        // Replace model and export manager
        canvasModel = newModel
        exportManager = ExportManager(canvasModel: newModel)

        // Rebind all references
        canvasView.canvasModel = newModel
        newModel.delegate = self
        newModel.layerStack.delegate = self
        layerPanel.layerStack = newModel.layerStack
        layerPanel.reload()
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true

        DispatchQueue.main.async { [weak self] in
            self?.canvasView.fitCanvasToView()
        }
    }
}

// MARK: - LayerPanelDelegate

extension MainWindowController: LayerPanelDelegate {
    func layerPanelDidSelectLayer(at index: Int) {
        canvasModel.layerStack.activeLayerIndex = index
        layerPanel.reload()
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    func layerPanelDidAddLayer() {
        canvasModel.layerStack.addLayer()
        layerPanel.reload()
    }

    func layerPanelDidDeleteLayer(at index: Int) {
        canvasModel.layerStack.deleteLayer(at: index)
        layerPanel.reload()
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    func layerPanelDidToggleVisibility(at index: Int) {
        canvasModel.layerStack.toggleVisibility(at: index)
        layerPanel.reload()
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    func layerPanelDidMergeDown(at index: Int) {
        canvasModel.layerStack.mergeDown(at: index)
        layerPanel.reload()
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    func layerPanelDidChangeOpacity(at index: Int, opacity: CGFloat) {
        canvasModel.layerStack.setOpacity(opacity, at: index)
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    func layerPanelDidToggleAlphaLock(at index: Int) {
        guard let layer = canvasModel.layerStack.layers[safe: index] else { return }
        layer.isAlphaLocked.toggle()
        layerPanel.reload()
    }

    func layerPanelDidToggleClippingMask(at index: Int) {
        guard let layer = canvasModel.layerStack.layers[safe: index] else { return }
        layer.isClippingMask.toggle()
        layerPanel.reload()
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    func layerPanelDidChangeBlendMode(at index: Int, mode: CGBlendMode) {
        guard let layer = canvasModel.layerStack.layers[safe: index] else { return }
        layer.blendMode = mode
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    func layerPanelDidMoveLayer(from src: Int, to dst: Int) {
        canvasModel.layerStack.moveLayer(from: src, to: dst)
        layerPanel.reload()
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    func layerPanelDidToggleReferenceLayer(at index: Int) {
        guard let layer = canvasModel.layerStack.layers[safe: index] else { return }
        layer.isReferenceLayer.toggle()
        layerPanel.reload()
    }

    func layerPanelDidToggleMask(at index: Int) {
        guard let layer = canvasModel.layerStack.layers[safe: index] else { return }
        if layer.hasMask {
            layer.deleteMask()
        } else {
            layer.createMask()
        }
        layerPanel.reload()
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    func layerPanelDidToggleMaskEditing(at index: Int) {
        guard let layer = canvasModel.layerStack.layers[safe: index] else { return }
        guard layer.hasMask else { return }
        layer.isMaskEditing.toggle()
        layerPanel.reload()
        canvasView.needsDisplay = true
    }

    func layerPanelDidConvertToMask(at index: Int) {
        let stack = canvasModel.layerStack
        guard index > 0,
              let sourceLayer = stack.layers[safe: index],
              let targetLayer = stack.layers[safe: index - 1],
              let sourceImage = sourceLayer.makeImage() else { return }

        // Extract alpha channel from source layer as the mask.
        // Where content was drawn (any color) → white (visible),
        // where transparent → black (hidden).
        let w = Int(sourceLayer.size.width)
        let h = Int(sourceLayer.size.height)

        // First render source into RGBA to read alpha
        guard let rgbaCtx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let rgbaData = rgbaCtx.data else { return }
        rgbaCtx.draw(sourceImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Build grayscale mask from alpha channel
        guard let grayCtx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let grayData = grayCtx.data else { return }

        let src = rgbaData.bindMemory(to: UInt8.self, capacity: w * h * 4)
        let dst = grayData.bindMemory(to: UInt8.self, capacity: w * h)
        for i in 0..<(w * h) {
            dst[i] = src[i * 4 + 3]  // alpha → mask luminance
        }

        guard let grayImage = grayCtx.makeImage() else { return }

        // Create mask on target layer and draw the grayscale image
        if !targetLayer.hasMask {
            targetLayer.createMask()
        }
        targetLayer.restoreMaskFromImage(grayImage)

        // Delete the source layer
        stack.deleteLayer(at: index)

        // Select the target layer
        stack.activeLayerIndex = min(index - 1, stack.layers.count - 1)

        layerPanel.reload()
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    func layerPanelDidApplyMask(at index: Int) {
        guard let layer = canvasModel.layerStack.layers[safe: index],
              layer.hasMask,
              let maskImage = layer.makeMaskImage(),
              let layerImage = layer.makeImage() else { return }

        let w = Int(layer.size.width)
        let h = Int(layer.size.height)

        // Read mask pixels (grayscale)
        guard let maskCtx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let maskData = maskCtx.data else { return }
        maskCtx.draw(maskImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        let maskPixels = maskData.bindMemory(to: UInt8.self, capacity: w * h)

        // Read layer pixels (RGBA)
        guard let rgbaCtx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let rgbaData = rgbaCtx.data else { return }
        rgbaCtx.draw(layerImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        let pixels = rgbaData.bindMemory(to: UInt8.self, capacity: w * h * 4)

        // Multiply alpha by mask value
        for i in 0..<(w * h) {
            let maskVal = maskPixels[i]
            if maskVal == 0 {
                // Fully masked out — clear pixel
                pixels[i * 4] = 0
                pixels[i * 4 + 1] = 0
                pixels[i * 4 + 2] = 0
                pixels[i * 4 + 3] = 0
            } else if maskVal < 255 {
                // Partial mask — scale all premultiplied components
                let scale = UInt16(maskVal)
                pixels[i * 4]     = UInt8((UInt16(pixels[i * 4]) * scale) / 255)
                pixels[i * 4 + 1] = UInt8((UInt16(pixels[i * 4 + 1]) * scale) / 255)
                pixels[i * 4 + 2] = UInt8((UInt16(pixels[i * 4 + 2]) * scale) / 255)
                pixels[i * 4 + 3] = UInt8((UInt16(pixels[i * 4 + 3]) * scale) / 255)
            }
        }

        guard let result = rgbaCtx.makeImage() else { return }

        canvasModel.snapshotActiveLayerForUndo()
        layer.restoreFromImage(result)
        layer.deleteMask()
        canvasModel.registerUndoForActiveLayer(actionName: "Apply Mask")

        layerPanel.reload()
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    func layerPanelDidRasterize(at index: Int) {
        guard let layer = canvasModel.layerStack.layers[safe: index],
              layer.isTextLayer else { return }
        canvasModel.snapshotActiveLayerForUndo()
        canvasModel.layerStack.rasterizeLayer(at: index)
        canvasModel.registerUndoForActiveLayer(actionName: "Rasterize Text")
        layerPanel.reload()
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    func layerPanelDidRequestEffects(at index: Int) {
        guard let layer = canvasModel.layerStack.layers[safe: index],
              let window = window else { return }
        let sheet = EffectsSheetController()
        sheet.initialEffects = layer.effects
        sheet.delegate = self
        Self.effectsPreviewOriginal = layer.effects
        sheet.presentAsSheet(on: window)
    }
}

// MARK: - EffectsSheetDelegate

extension MainWindowController: EffectsSheetDelegate {
    private static var effectsPreviewOriginal: LayerEffects?

    func effectsSheetDidApply(_ effects: LayerEffects) {
        guard let layer = canvasModel.layerStack.activeLayer else { return }
        canvasModel.snapshotActiveLayerForUndo()
        layer.effects = effects
        canvasModel.registerUndoForActiveLayer(actionName: "Layer Effects")
        Self.effectsPreviewOriginal = nil
        layerPanel.reload()
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    func effectsSheetDidCancel() {
        guard let layer = canvasModel.layerStack.activeLayer else { return }
        if let original = Self.effectsPreviewOriginal {
            layer.effects = original
        }
        Self.effectsPreviewOriginal = nil
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    func effectsSheetDidChangeParams(_ effects: LayerEffects) {
        guard let layer = canvasModel.layerStack.activeLayer else { return }
        layer.effects = effects
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }
}

// MARK: - Import Image

extension MainWindowController {
    func importImageAsLayer() {
        guard let window = window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an image to import as a new layer"

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadImageAsLayer(from: url)
        }
    }

    private func loadImageAsLayer(from url: URL) {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else { return }

        let name = url.deletingPathExtension().lastPathComponent
        canvasModel.layerStack.addLayerFromImage(cgImage, name: name)
        layerPanel.reload()
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    func openImageAsCanvas() {
        guard let window = window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an image to open as canvas background"

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadImageAsCanvas(from: url)
        }
    }

    private func loadImageAsCanvas(from url: URL) {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else { return }

        let imageSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let name = url.deletingPathExtension().lastPathComponent

        // Create a new canvas matching the image dimensions
        let newModel = CanvasModel(size: imageSize)

        // Draw the image onto the background layer (layer 0) at full size
        if let bgLayer = newModel.layerStack.activeLayer {
            bgLayer.name = name
            bgLayer.context.draw(cgImage, in: CGRect(origin: .zero, size: imageSize))
        }

        // Add an empty layer on top for drawing
        newModel.layerStack.addLayer()

        // Replace model and export manager
        canvasModel = newModel
        exportManager = ExportManager(canvasModel: newModel)

        // Rebind all references
        canvasView.canvasModel = newModel
        newModel.delegate = self
        newModel.layerStack.delegate = self
        layerPanel.layerStack = newModel.layerStack
        layerPanel.reload()
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true

        DispatchQueue.main.async { [weak self] in
            self?.canvasView.fitCanvasToView()
        }
    }
}

// MARK: - CanvasModelDelegate

extension MainWindowController: CanvasModelDelegate {
    func canvasDidChange() {
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
        layerPanel.reload()
    }
}

// MARK: - LayerStackDelegate

extension MainWindowController: LayerStackDelegate {
    func layerStackDidChange() {
        layerPanel.reload()
    }
}

// MARK: - Filters

extension MainWindowController {

    /// Original layer image saved when filter sheet opens, for preview/cancel
    private static var filterPreviewOriginal: CGImage?

    func applyFilter(_ type: FilterType, params: [String: Double] = [:]) {
        guard let layer = canvasModel.layerStack.activeLayer,
              let image = layer.makeImage() else { return }

        canvasModel.snapshotActiveLayerForUndo()

        let result: CGImage?
        if let sel = canvasModel.selectionMask, !sel.isEmpty {
            result = FilterEngine.applyWithSelection(type, params: params,
                                                      to: image, selection: sel)
        } else {
            result = FilterEngine.apply(type, params: params, to: image)
        }

        guard let filtered = result else { return }
        layer.restoreFromImage(filtered)
        canvasModel.registerUndoForActiveLayer(actionName: type.displayName)
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    func showFilterSheet(_ type: FilterType) {
        guard let window = window else { return }
        // Save original for preview
        Self.filterPreviewOriginal = canvasModel.layerStack.activeLayer?.makeImage()
        canvasModel.snapshotActiveLayerForUndo()

        let sheet = FilterSheetController(filter: type)
        sheet.delegate = self
        sheet.presentAsSheet(on: window)
    }

    fileprivate func previewFilter(_ type: FilterType, params: [String: Double]) {
        guard let layer = canvasModel.layerStack.activeLayer,
              let original = Self.filterPreviewOriginal else { return }

        let result: CGImage?
        if let sel = canvasModel.selectionMask, !sel.isEmpty {
            result = FilterEngine.applyWithSelection(type, params: params,
                                                      to: original, selection: sel)
        } else {
            result = FilterEngine.apply(type, params: params, to: original)
        }

        guard let filtered = result else { return }
        layer.restoreFromImage(filtered)
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    fileprivate func cancelFilterPreview() {
        guard let layer = canvasModel.layerStack.activeLayer,
              let original = Self.filterPreviewOriginal else { return }
        layer.restoreFromImage(original)
        Self.filterPreviewOriginal = nil
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    fileprivate func commitFilterPreview(_ type: FilterType) {
        // Layer already has the previewed result — just register undo
        canvasModel.registerUndoForActiveLayer(actionName: type.displayName)
        Self.filterPreviewOriginal = nil
    }
}

// MARK: - FilterSheetDelegate

extension MainWindowController: FilterSheetDelegate {
    func filterSheetDidApply(_ filter: FilterType, params: [String: Double]) {
        // Final preview with exact params, then commit
        previewFilter(filter, params: params)
        commitFilterPreview(filter)
    }

    func filterSheetDidCancel() {
        cancelFilterPreview()
    }

    func filterSheetDidChangeParams(_ filter: FilterType, params: [String: Double]) {
        previewFilter(filter, params: params)
    }
}

// MARK: - ToolManagerDelegate

extension MainWindowController: ToolManagerDelegate {
    func toolDidChange(to tool: Tool) {
        statusBar.updateTool(tool.name)
        toolbarView.updateActiveTool(tool.name)
        window?.invalidateCursorRects(for: canvasView)
    }

    func colorDidChange(to color: NSColor) {
        toolbarView.updateColor(color)
        colorPickerSidebar.setColor(color)
    }

    func brushDidChange(to preset: BrushPreset) {
        sidebarSliders.updateBrushSize(preset.maxRadius)
        sidebarSliders.updateOpacity(preset.opacity)
        toolbarView.updateActiveTool(preset.name)
    }
}

// MARK: - TextToolSheetDelegate

extension MainWindowController: TextToolSheetDelegate {
    func textToolDidRequestSheet() {
        guard let window = window else { return }
        let sheet = TextSheetController()
        sheet.delegate = self
        sheet.initialColor = toolManager.textTool.previewColor

        // Pre-fill for re-edit mode
        if let existing = toolManager.textTool.editingExistingLayer,
           let tc = existing.textContent {
            sheet.configureForReEdit(content: tc)
        }

        sheet.presentAsSheet(on: window)
    }
}

// MARK: - TextSheetDelegate

extension MainWindowController: TextSheetDelegate {
    func textSheetDidApply(text: String, fontName: String, fontSize: CGFloat,
                           isBold: Bool, isItalic: Bool, color: NSColor) {
        let textTool = toolManager.textTool
        textTool.updatePreview(text: text, fontName: fontName, fontSize: fontSize,
                               isBold: isBold, isItalic: isItalic, color: color)
        textTool.commitText(canvas: canvasView)
    }

    func textSheetDidCancel() {
        toolManager.textTool.cancelText(canvas: canvasView)
    }

    func textSheetDidChangeParams(text: String, fontName: String, fontSize: CGFloat,
                                  isBold: Bool, isItalic: Bool, color: NSColor) {
        let textTool = toolManager.textTool
        textTool.updatePreview(text: text, fontName: fontName, fontSize: fontSize,
                               isBold: isBold, isItalic: isItalic, color: color)
        canvasView.needsDisplay = true
    }
}

// MARK: - KnobStripDelegate

extension MainWindowController: KnobStripDelegate {
    func knobStripDidChangeRotation(_ degrees: CGFloat) {
        canvasView.canvasTransform.canvasCenter = CGPoint(
            x: canvasModel.canvasSize.width / 2,
            y: canvasModel.canvasSize.height / 2
        )
        canvasView.canvasTransform.rotation = degrees
        canvasView.needsDisplay = true
        NotificationCenter.default.post(name: .canvasTransformChanged, object: canvasView)
    }

    func knobStripDidChangeZoom(_ scale: CGFloat) {
        let center = CGPoint(x: canvasView.bounds.midX, y: canvasView.bounds.midY)
        let canvasPt = canvasView.canvasTransform.viewToCanvas(center)
        canvasView.canvasTransform.scale = scale
        // Recompute offset to keep center stable
        let viewAfter = canvasView.canvasTransform.canvasToView(canvasPt)
        canvasView.canvasTransform.offset.x += center.x - viewAfter.x
        canvasView.canvasTransform.offset.y += center.y - viewAfter.y
        canvasView.needsDisplay = true
        statusBar.updateZoom(canvasView.canvasTransform.zoomPercentage)
        toolbarView.updateZoom(canvasView.canvasTransform.zoomPercentage)
    }

    func knobStripDidChangeBrushSize(_ size: CGFloat) {
        toolManager.currentBrushPreset.maxRadius = size
        sidebarSliders.updateBrushSize(size)
        canvasView.showBrushSizePreview(radius: size)
    }
}

// MARK: - AI Integration

extension MainWindowController {
    func showAISheet() {
        guard let window = window else { return }
        let sheet = AISheetController()
        sheet.delegate = self
        sheet.presentAsSheet(on: window)
    }
}

extension MainWindowController: AISheetDelegate {
    func aiSheetDidProduceImage(_ image: CGImage, mode: AIMode) {
        // Object Select: convert mask image to a SelectionMask
        if mode.producesSelectionMask {
            let w = Int(canvasModel.canvasSize.width)
            let h = Int(canvasModel.canvasSize.height)
            if let mask = SelectionMask.fromMaskImage(image, width: w, height: h) {
                canvasModel.selectionMask = mask
                canvasView.updateSelectionDisplay()
            }
            canvasView.compositeDirty = true
            canvasView.needsDisplay = true
            return
        }

        let layerName: String
        switch mode {
        case .generate:         layerName = "AI Generated"
        case .referencePose:    layerName = "AI Pose Reference"
        case .styleTransfer:    layerName = "AI Style Transfer"
        case .sketchToPainting: layerName = "AI Painting"
        case .autoColor:        layerName = "AI Colored"
        case .lineArt:          layerName = "AI Line Art"
        case .upscale:          layerName = "AI Upscaled"
        case .bgRemove:         layerName = "AI No Background"
        case .inpaint:          layerName = "AI Inpainted"
        case .textureFill:      layerName = "AI Texture"
        case .outpaint:         layerName = "AI Outpainted"
        case .variations:       layerName = "AI Variation"
        default:                layerName = "AI Result"
        }

        // For inpaint with an active selection, clip the result to the selection
        if mode == .inpaint, let mask = canvasModel.selectionMask, !mask.isEmpty,
           let maskImage = mask.makeMaskImage() {
            let w = Int(canvasModel.canvasSize.width)
            let h = Int(canvasModel.canvasSize.height)

            guard let ctx = CGContext(
                data: nil, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }

            let fullRect = CGRect(x: 0, y: 0, width: w, height: h)
            ctx.clip(to: fullRect, mask: maskImage)
            ctx.draw(image, in: fullRect)

            if let clipped = ctx.makeImage() {
                canvasModel.layerStack.addLayerFromImage(clipped, name: layerName)
            }
        } else {
            canvasModel.layerStack.addLayerFromImage(image, name: layerName)
        }
        layerPanel.reload()
        canvasView.compositeDirty = true
        canvasView.needsDisplay = true
    }

    func aiSheetDidProduceText(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "AI Description"
        alert.informativeText = text
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        if let window = window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }

    func aiSheetRequestsCanvasImage() -> CGImage? {
        return canvasModel.layerStack.compositeImage()
    }

    func aiSheetRequestsSelectionMask() -> CGImage? {
        return canvasModel.selectionMask?.makeMaskImage()
    }

    func aiSheetRequestsCanvasSize() -> CGSize {
        return canvasModel.canvasSize
    }
}
