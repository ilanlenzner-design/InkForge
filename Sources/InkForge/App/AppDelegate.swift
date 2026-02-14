import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    var mainWindowController: MainWindowController?
    var tabletManager: TabletManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        tabletManager = TabletManager()
        tabletManager?.setup()

        let canvasModel = CanvasModel(size: CGSize(width: 2048, height: 2048))
        mainWindowController = MainWindowController(canvasModel: canvasModel)
        mainWindowController?.showWindow(nil)

        setupMainMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tabletManager?.teardown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Main Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About InkForge", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit InkForge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Canvas...", action: #selector(newCanvas), keyEquivalent: "n")
        fileMenu.items.last?.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Export as PNG...", action: #selector(exportPNG), keyEquivalent: "e")
        fileMenu.items.last?.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(withTitle: "Export as JPEG...", action: #selector(exportJPEG), keyEquivalent: "e")
        fileMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "Export as TIFF...", action: #selector(exportTIFF), keyEquivalent: "")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Open Image as Canvas...", action: #selector(openImageAsCanvas), keyEquivalent: "o")
        fileMenu.items.last?.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(withTitle: "Import Image as Layer...", action: #selector(importImage), keyEquivalent: "i")
        fileMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: #selector(undoAction), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: #selector(redoAction), keyEquivalent: "z")
        editMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Zoom to Fit", action: #selector(zoomToFit), keyEquivalent: "0")
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(zoomActualSize), keyEquivalent: "1")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Toggle Layers Panel", action: #selector(toggleLayerPanel), keyEquivalent: "l")
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Select menu
        let selectMenu = NSMenu(title: "Select")
        selectMenu.addItem(withTitle: "Select All", action: #selector(selectAll), keyEquivalent: "a")
        selectMenu.addItem(withTitle: "Deselect", action: #selector(deselect), keyEquivalent: "d")
        selectMenu.addItem(withTitle: "Invert Selection", action: #selector(invertSelection), keyEquivalent: "i")
        selectMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        let selectMenuItem = NSMenuItem()
        selectMenuItem.submenu = selectMenu
        mainMenu.addItem(selectMenuItem)

        // Filter menu
        let filterMenu = NSMenu(title: "Filter")
        filterMenu.addItem(withTitle: "Invert Colors", action: #selector(filterInvertColors), keyEquivalent: "")
        filterMenu.addItem(withTitle: "Desaturate", action: #selector(filterDesaturate), keyEquivalent: "u")
        filterMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        filterMenu.addItem(.separator())
        filterMenu.addItem(withTitle: "Gaussian Blur...", action: #selector(filterGaussianBlur), keyEquivalent: "")
        filterMenu.addItem(withTitle: "Motion Blur...", action: #selector(filterMotionBlur), keyEquivalent: "")
        filterMenu.addItem(withTitle: "Sharpen...", action: #selector(filterSharpen), keyEquivalent: "")
        filterMenu.addItem(withTitle: "Noise...", action: #selector(filterNoise), keyEquivalent: "")
        filterMenu.addItem(.separator())
        filterMenu.addItem(withTitle: "Hue/Saturation...", action: #selector(filterHueSaturation), keyEquivalent: "")
        filterMenu.addItem(withTitle: "Brightness/Contrast...", action: #selector(filterBrightnessContrast), keyEquivalent: "")
        filterMenu.addItem(.separator())
        filterMenu.addItem(withTitle: "Posterize...", action: #selector(filterPosterize), keyEquivalent: "")
        filterMenu.addItem(withTitle: "Pixelate...", action: #selector(filterPixelate), keyEquivalent: "")
        let filterMenuItem = NSMenuItem()
        filterMenuItem.submenu = filterMenu
        mainMenu.addItem(filterMenuItem)

        // Layer menu
        let layerMenu = NSMenu(title: "Layer")
        layerMenu.addItem(withTitle: "New Layer", action: #selector(newLayer), keyEquivalent: "n")
        layerMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        layerMenu.addItem(withTitle: "Delete Layer", action: #selector(deleteLayer), keyEquivalent: "")
        layerMenu.addItem(withTitle: "Merge Down", action: #selector(mergeDown), keyEquivalent: "")
        layerMenu.addItem(.separator())
        layerMenu.addItem(withTitle: "Rasterize Text Layer", action: #selector(rasterizeTextLayer), keyEquivalent: "")
        let layerMenuItem = NSMenuItem()
        layerMenuItem.submenu = layerMenu
        mainMenu.addItem(layerMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    // MARK: - Menu Actions

    @objc private func newCanvas() {
        mainWindowController?.showNewCanvasSheet()
    }

    @objc private func exportPNG() {
        mainWindowController?.exportImage(format: "png")
    }

    @objc private func exportJPEG() {
        mainWindowController?.exportImage(format: "jpeg")
    }

    @objc private func exportTIFF() {
        mainWindowController?.exportImage(format: "tiff")
    }

    @objc private func openImageAsCanvas() {
        mainWindowController?.openImageAsCanvas()
    }

    @objc private func importImage() {
        mainWindowController?.importImageAsLayer()
    }

    @objc private func undoAction() {
        mainWindowController?.canvasModel.undo()
    }

    @objc private func redoAction() {
        mainWindowController?.canvasModel.redo()
    }

    @objc private func zoomToFit() {
        mainWindowController?.canvasView.fitCanvasToView()
    }

    @objc private func zoomActualSize() {
        mainWindowController?.canvasView.zoomTo100()
    }

    @objc private func toggleLayerPanel() {
        mainWindowController?.toggleLayerPanel()
    }

    @objc private func newLayer() {
        mainWindowController?.layerPanelDidAddLayer()
    }

    @objc private func deleteLayer() {
        guard let wc = mainWindowController else { return }
        wc.layerPanelDidDeleteLayer(at: wc.canvasModel.layerStack.activeLayerIndex)
    }

    @objc private func mergeDown() {
        guard let wc = mainWindowController else { return }
        wc.layerPanelDidMergeDown(at: wc.canvasModel.layerStack.activeLayerIndex)
    }

    @objc private func rasterizeTextLayer() {
        mainWindowController?.rasterizeActiveTextLayer()
    }

    @objc private func selectAll() {
        guard let wc = mainWindowController else { return }
        wc.canvasModel.selectAll()
        wc.canvasView.updateSelectionDisplay()
    }

    @objc private func deselect() {
        guard let wc = mainWindowController else { return }
        wc.canvasModel.deselect()
        wc.canvasView.updateSelectionDisplay()
    }

    @objc private func invertSelection() {
        guard let wc = mainWindowController else { return }
        wc.canvasModel.invertSelection()
        wc.canvasView.updateSelectionDisplay()
    }

    // MARK: - Filter Actions

    @objc private func filterInvertColors() {
        mainWindowController?.applyFilter(.invertColors)
    }

    @objc private func filterDesaturate() {
        mainWindowController?.applyFilter(.desaturate)
    }

    @objc private func filterGaussianBlur() {
        mainWindowController?.showFilterSheet(.gaussianBlur)
    }

    @objc private func filterMotionBlur() {
        mainWindowController?.showFilterSheet(.motionBlur)
    }

    @objc private func filterSharpen() {
        mainWindowController?.showFilterSheet(.sharpen)
    }

    @objc private func filterNoise() {
        mainWindowController?.showFilterSheet(.noise)
    }

    @objc private func filterHueSaturation() {
        mainWindowController?.showFilterSheet(.hueSaturation)
    }

    @objc private func filterBrightnessContrast() {
        mainWindowController?.showFilterSheet(.brightnessContrast)
    }

    @objc private func filterPosterize() {
        mainWindowController?.showFilterSheet(.posterize)
    }

    @objc private func filterPixelate() {
        mainWindowController?.showFilterSheet(.pixelate)
    }
}
