import AppKit

class CanvasView: NSView {

    var canvasModel: CanvasModel!
    var toolManager: ToolManager!
    var canvasTransform = CanvasTransform()

    var currentStroke: StrokeData?
    var compositeDirty: Bool = true
    private var compositeCache: CGImage?
    private let strokeRenderer = StrokeRenderer()

    // Temporary bitmap for the in-progress stroke (avoids re-rendering full stroke each frame)
    private var strokeBitmap: CGContext?
    private var strokeBitmapDirty: Bool = false

    // Marching ants (GPU-animated via CAShapeLayer)
    private var antsWhiteLayer: CAShapeLayer?
    private var antsBlackLayer: CAShapeLayer?
    private var selectionDirty = true
    private var lastAntsTransform: CGAffineTransform = .identity

    // Brush cursor (follows mouse)
    private var lastMouseViewPoint: CGPoint?
    private var trackingArea: NSTrackingArea?
    private var isMouseButtonDown = false

    // Right-click / pen barrel button panning
    private var rightDragLastPoint: CGPoint?

    // Brush size center preview (temporary, shown when adjusting via knob)
    private var brushSizePreviewRadius: CGFloat = 0
    private var brushSizePreviewAlpha: CGFloat = 0
    private var brushSizePreviewTimer: Timer?

    // MARK: - NSView Configuration

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 0.3, alpha: 1).cgColor
        setupTrackingArea()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        setupTrackingArea()
    }

    private func setupTrackingArea() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: toolManager?.activeTool.cursor ?? .crosshair)
    }

    // MARK: - Coordinate Conversion

    func canvasPoint(from viewPoint: CGPoint) -> CGPoint {
        return canvasTransform.viewToCanvas(viewPoint)
    }

    func invalidateForNewSegment(from p1: StrokePoint, to p2: StrokePoint, maxRadius: CGFloat) {
        // Invalidate the entire view to avoid clipping the in-progress stroke.
        // The display system coalesces redraws, so this is fine at ~60fps.
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let canvasSize = canvasModel.canvasSize

        // 1. Fill background
        ctx.setFillColor(NSColor(white: 0.3, alpha: 1).cgColor)
        ctx.fill(bounds)

        // 2. Apply canvas transform (zoom + pan + rotation)
        canvasTransform.canvasCenter = CGPoint(x: canvasSize.width / 2,
                                                y: canvasSize.height / 2)
        ctx.saveGState()
        ctx.concatenate(canvasTransform.affineTransform)

        // 3. Draw checkerboard behind the canvas area
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        drawCheckerboard(in: ctx, rect: canvasRect)

        // 4. Draw canvas border
        ctx.setStrokeColor(NSColor.gray.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(1.0 / canvasTransform.scale)
        ctx.stroke(canvasRect)

        // 5. Draw layer composite.
        //    The composite CGImage has bottom-left origin (standard CGContext).
        //    Our NSView is flipped (top-left origin), and we've concatenated the canvas transform.
        //    We need to flip Y when drawing the image so it appears right-side-up.
        if compositeDirty {
            compositeCache = canvasModel.layerStack.compositeImage()
            compositeDirty = false
        }
        if let composite = compositeCache {
            ctx.saveGState()
            // Flip within the canvas rect: translate to bottom of canvas, then invert Y
            ctx.translateBy(x: 0, y: canvasSize.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(composite, in: canvasRect)
            ctx.restoreGState()
        }

        // 6. Draw in-progress stroke (directly in canvas coordinates - no flip needed
        //    because we're drawing into the flipped NSView context, same as preview)
        if let stroke = currentStroke {
            strokeRenderer.renderStroke(stroke, into: ctx, preview: true)

            // Live preview of symmetry mirrors
            let sym = canvasModel.symmetryMode
            if sym != .off {
                for mirror in stroke.symmetryMirrors(mode: sym,
                        axisX: canvasModel.effectiveSymmetryAxisX,
                        axisY: canvasModel.effectiveSymmetryAxisY) {
                    strokeRenderer.renderStroke(mirror, into: ctx, preview: true)
                }
            }
        }

        // 6b. Draw symmetry guide lines
        if canvasModel.symmetryMode != .off {
            drawSymmetryGuides(in: ctx, canvasSize: canvasSize)
        }

        // 6c. Draw mask overlay when editing a layer mask
        if let layer = canvasModel.layerStack.activeLayer,
           layer.isMaskEditing, let maskImage = layer.makeMaskImage() {
            drawMaskOverlay(maskImage, in: ctx, canvasSize: canvasSize)
        }

        // 7. Draw tool overlay (selection preview, transform handles)
        toolManager?.activeTool.drawOverlay(in: ctx, canvas: self)

        // 8. Draw selection dim overlay (ants are on a separate CAShapeLayer)
        if let mask = canvasModel.selectionMask, !mask.isEmpty {
            drawSelectionOverlay(mask, in: ctx, canvasSize: canvasSize)
        }

        // Update ants layers if selection changed or transform changed
        let currentTransform = canvasTransform.affineTransform
        if selectionDirty || (antsWhiteLayer != nil && lastAntsTransform != currentTransform) {
            updateAntsLayers()
            selectionDirty = false
            lastAntsTransform = currentTransform
        }

        // 9. Draw brush cursor circle (in canvas coordinates)
        if isBrushToolActive, !isMouseButtonDown, currentStroke == nil,
           let viewPt = lastMouseViewPoint {
            let canvasPt = canvasTransform.viewToCanvas(viewPt)
            let radius = toolManager.currentBrushPreset.maxRadius
            drawBrushCursor(at: canvasPt, radius: radius, in: ctx)
        }

        ctx.restoreGState()

        // 10. Draw brush size center preview (in view coordinates, outside canvas transform)
        if brushSizePreviewAlpha > 0.01 {
            drawBrushSizeCenterPreview(in: ctx)
        }
    }

    private func drawSelectionOverlay(_ mask: SelectionMask, in ctx: CGContext, canvasSize: CGSize) {
        guard let overlay = mask.makeDimOverlayImage() else { return }
        let rect = CGRect(origin: .zero, size: canvasSize)

        // Blit the pre-rendered dim overlay (flip for CGImage bottom-up convention)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: canvasSize.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(overlay, in: rect)
        ctx.restoreGState()
    }

    // MARK: - CAShapeLayer Marching Ants

    private func updateAntsLayers() {
        guard let mask = canvasModel?.selectionMask, !mask.isEmpty else {
            removeAntsLayers()
            return
        }

        let antsPath = mask.marchingAntsPath()

        // Transform path from canvas coords to view coords
        var transform = canvasTransform.affineTransform
        let viewPath = antsPath.copy(using: &transform)

        let lineWidth: CGFloat = 1.0

        // Create layers if needed
        if antsWhiteLayer == nil {
            let white = CAShapeLayer()
            white.fillColor = nil
            white.strokeColor = NSColor.white.cgColor
            white.lineWidth = lineWidth
            white.zPosition = 100
            layer?.addSublayer(white)
            antsWhiteLayer = white

            let black = CAShapeLayer()
            black.fillColor = nil
            black.strokeColor = NSColor.black.cgColor
            black.lineWidth = lineWidth
            black.lineDashPattern = [4, 4]
            black.zPosition = 101
            layer?.addSublayer(black)
            antsBlackLayer = black

            // Continuous dash animation (GPU-driven, no timer needed)
            let anim = CABasicAnimation(keyPath: "lineDashPhase")
            anim.fromValue = 0
            anim.toValue = 8  // sum of dash pattern
            anim.duration = 0.4
            anim.repeatCount = .infinity
            black.add(anim, forKey: "marchingAnts")
        }

        // Update paths (no animation needed for path changes)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        antsWhiteLayer?.path = viewPath
        antsBlackLayer?.path = viewPath
        CATransaction.commit()
    }

    private func removeAntsLayers() {
        antsWhiteLayer?.removeFromSuperlayer()
        antsBlackLayer?.removeFromSuperlayer()
        antsWhiteLayer = nil
        antsBlackLayer = nil
    }

    private func drawCheckerboard(in ctx: CGContext, rect: CGRect) {
        let tileSize: CGFloat = 16

        // Fill white
        ctx.setFillColor(NSColor(white: 0.95, alpha: 1).cgColor)
        ctx.fill(rect)

        // Dark tiles
        ctx.setFillColor(NSColor(white: 0.85, alpha: 1).cgColor)
        let startX = rect.minX
        let startY = rect.minY
        let cols = Int(ceil(rect.width / tileSize))
        let rows = Int(ceil(rect.height / tileSize))

        for row in 0..<rows {
            for col in 0..<cols {
                if (col + row) % 2 == 0 {
                    let x = startX + CGFloat(col) * tileSize
                    let y = startY + CGFloat(row) * tileSize
                    ctx.fill(CGRect(x: x, y: y, width: tileSize, height: tileSize))
                }
            }
        }
    }

    private func drawMaskOverlay(_ maskImage: CGImage, in ctx: CGContext, canvasSize: CGSize) {
        let rect = CGRect(origin: .zero, size: canvasSize)

        // Invert the mask: areas that are dark in the mask (hidden) become bright in the inverted mask.
        // Then clip to the inverted mask and fill with semi-transparent red.
        let width = maskImage.width
        let height = maskImage.height

        guard let invertCtx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return }

        // Draw original mask
        invertCtx.draw(maskImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Invert pixel data
        if let data = invertCtx.data {
            let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
            for i in 0..<(width * height) {
                pixels[i] = 255 - pixels[i]
            }
        }

        guard let invertedMask = invertCtx.makeImage() else { return }

        // The mask is in bottom-left coords, we're drawing in top-left (flipped).
        // Use clip(to:mask:) which works in the current CTM coordinate space.
        // Since we already flipped, need to flip the mask draw too.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: canvasSize.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.clip(to: rect, mask: invertedMask)
        ctx.translateBy(x: 0, y: canvasSize.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(NSColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 0.35).cgColor)
        ctx.fill(rect)
        ctx.restoreGState()
    }

    private func drawSymmetryGuides(in ctx: CGContext, canvasSize: CGSize) {
        let lineWidth = 1.0 / canvasTransform.scale
        let dashLen = 6.0 / canvasTransform.scale

        ctx.saveGState()
        ctx.setStrokeColor(NSColor.cyan.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineDash(phase: 0, lengths: [dashLen, dashLen])

        let mode = canvasModel.symmetryMode
        if mode == .vertical || mode == .quadrant {
            let x = canvasModel.effectiveSymmetryAxisX
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: canvasSize.height))
            ctx.strokePath()
        }
        if mode == .horizontal || mode == .quadrant {
            let y = canvasModel.effectiveSymmetryAxisY
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: canvasSize.width, y: y))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: - Brush Cursor

    private var isBrushToolActive: Bool {
        guard let tool = toolManager?.activeTool else { return false }
        return tool is PenTool || tool is EraserTool || tool is SmudgeTool
    }

    private func drawBrushCursor(at canvasPt: CGPoint, radius: CGFloat, in ctx: CGContext) {
        let lineWidth = 1.0 / canvasTransform.scale
        let dashLen = 3.0 / canvasTransform.scale

        ctx.saveGState()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.addEllipse(in: CGRect(x: canvasPt.x - radius, y: canvasPt.y - radius,
                                   width: radius * 2, height: radius * 2))
        ctx.strokePath()

        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineDash(phase: 0, lengths: [dashLen, dashLen])
        ctx.addEllipse(in: CGRect(x: canvasPt.x - radius, y: canvasPt.y - radius,
                                   width: radius * 2, height: radius * 2))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawBrushSizeCenterPreview(in ctx: CGContext) {
        let viewCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        let viewRadius = brushSizePreviewRadius * canvasTransform.scale
        let alpha = brushSizePreviewAlpha

        ctx.saveGState()
        ctx.setStrokeColor(NSColor.inkAccent.withAlphaComponent(alpha * 0.9).cgColor)
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.addEllipse(in: CGRect(x: viewCenter.x - viewRadius, y: viewCenter.y - viewRadius,
                                   width: viewRadius * 2, height: viewRadius * 2))
        ctx.strokePath()

        // Size label
        let text = "\(Int(brushSizePreviewRadius * 2)) px"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.inkAccent.withAlphaComponent(alpha),
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        str.draw(at: NSPoint(x: viewCenter.x - size.width / 2,
                              y: viewCenter.y + viewRadius + 8))
        ctx.restoreGState()
    }

    /// Call this to show a temporary brush size preview in the center of the canvas.
    func showBrushSizePreview(radius: CGFloat) {
        brushSizePreviewRadius = radius
        brushSizePreviewAlpha = 1.0
        needsDisplay = true

        brushSizePreviewTimer?.invalidate()
        brushSizePreviewTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.brushSizePreviewAlpha -= 0.04
            if self.brushSizePreviewAlpha <= 0 {
                self.brushSizePreviewAlpha = 0
                timer.invalidate()
                self.brushSizePreviewTimer = nil
            }
            self.needsDisplay = true
        }
    }

    // MARK: - Selection Display

    func updateSelectionDisplay() {
        selectionDirty = true
        needsDisplay = true
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        isMouseButtonDown = true
        lastMouseViewPoint = nil  // hide brush cursor immediately
        toolManager?.handleMouseDown(event: event, in: self)
    }

    override func mouseDragged(with event: NSEvent) {
        toolManager?.handleMouseDragged(event: event, in: self)
    }

    override func mouseUp(with event: NSEvent) {
        isMouseButtonDown = false
        lastMouseViewPoint = convert(event.locationInWindow, from: nil)
        toolManager?.handleMouseUp(event: event, in: self)
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        lastMouseViewPoint = convert(event.locationInWindow, from: nil)
        if isBrushToolActive { needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        lastMouseViewPoint = nil
        needsDisplay = true
    }

    // Right-click / pen barrel button → pan canvas
    override func rightMouseDown(with event: NSEvent) {
        rightDragLastPoint = event.locationInWindow
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard let last = rightDragLastPoint else { return }
        let current = event.locationInWindow
        canvasTransform.offset.x += current.x - last.x
        canvasTransform.offset.y -= current.y - last.y
        rightDragLastPoint = current
        needsDisplay = true
        NotificationCenter.default.post(name: .canvasTransformChanged, object: self)
    }

    override func rightMouseUp(with event: NSEvent) {
        rightDragLastPoint = nil
    }

    override func tabletProximity(with event: NSEvent) {
        toolManager?.handleProximity(event: event)
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - Scroll / Zoom

    override func scrollWheel(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.option, .command])
        if !mods.isEmpty {
            // Option+scroll or Cmd+scroll = zoom
            let factor: CGFloat = event.scrollingDeltaY > 0 ? 0.95 : 1.05
            let viewPoint = convert(event.locationInWindow, from: nil)
            canvasTransform.zoom(by: factor, centeredOn: viewPoint)
        } else {
            // Plain scroll = pan
            canvasTransform.offset.x += event.scrollingDeltaX
            canvasTransform.offset.y -= event.scrollingDeltaY
        }
        needsDisplay = true
        NotificationCenter.default.post(name: .canvasTransformChanged, object: self)
    }

    override func magnify(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        canvasTransform.zoom(by: 1 + event.magnification, centeredOn: viewPoint)
        needsDisplay = true
        NotificationCenter.default.post(name: .canvasTransformChanged, object: self)
    }

    override func rotate(with event: NSEvent) {
        canvasTransform.rotation -= CGFloat(event.rotation)
        needsDisplay = true
        NotificationCenter.default.post(name: .canvasTransformChanged, object: self)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard let toolManager = toolManager else { return }

        // Let active tool handle key first (e.g. Transform Enter/Escape)
        if toolManager.activeTool.handleKeyDown(event: event, canvas: self) {
            return
        }

        switch event.keyCode {
        case 53: // Escape — deselect
            canvasModel.deselect()
            updateSelectionDisplay()
        case 49: // Space
            if !event.isARepeat {
                toolManager.activatePanTemporarily()
                window?.invalidateCursorRects(for: self)
            }
        default:
            handleKeyShortcut(event)
        }
    }

    override func keyUp(with event: NSEvent) {
        switch event.keyCode {
        case 49: // Space
            toolManager?.deactivateTemporaryTool()
            window?.invalidateCursorRects(for: self)
        default:
            break
        }
    }

    private func handleKeyShortcut(_ event: NSEvent) {
        guard let toolManager = toolManager, let chars = event.characters else { return }

        // Cmd+D = Deselect, Cmd+Shift+I = Invert Selection, Cmd+A = Select All
        if event.modifierFlags.contains(.command) {
            switch chars.lowercased() {
            case "d":
                canvasModel.deselect()
                updateSelectionDisplay()
                return
            case "a":
                canvasModel.selectAll()
                updateSelectionDisplay()
                return
            default:
                break
            }
            if event.modifierFlags.contains(.shift) {
                switch chars.lowercased() {
                case "i":
                    canvasModel.invertSelection()
                    updateSelectionDisplay()
                    return
                case "a":
                    // Cmd+Shift+A — open AI sheet
                    if let wc = window?.windowController as? MainWindowController {
                        wc.showAISheet()
                    }
                    return
                default:
                    break
                }
            }
        }

        switch chars {
        case "b":
            toolManager.selectTool(toolManager.penTool)
            toolManager.currentBrushPreset = .defaultRound
        case "c":
            toolManager.selectTool(toolManager.penTool)
            toolManager.currentBrushPreset = .defaultCalligraphy
        case "a":
            toolManager.selectTool(toolManager.penTool)
            toolManager.currentBrushPreset = .defaultAirbrush
        case "s":
            toolManager.selectTool(toolManager.smudgeTool)
        case "g":
            toolManager.selectTool(toolManager.fillTool)
        case "e":
            toolManager.selectTool(toolManager.eraserTool)
        case "h":
            toolManager.selectTool(toolManager.panTool)
        case "z":
            toolManager.selectTool(toolManager.zoomTool)
        case "i":
            toolManager.selectTool(toolManager.eyedropperTool)
        case "m":
            toolManager.selectTool(toolManager.selectionTool)
        case "v":
            toolManager.selectTool(toolManager.transformTool)
        case "w":
            toolManager.selectionTool.shape = .wand
            toolManager.selectTool(toolManager.selectionTool)
        case "l":
            toolManager.selectionTool.shape = .lasso
            toolManager.selectTool(toolManager.selectionTool)
        case "x":
            // Cycle symmetry: off → vertical → horizontal → quadrant → off
            switch canvasModel.symmetryMode {
            case .off:        canvasModel.symmetryMode = .vertical
            case .vertical:   canvasModel.symmetryMode = .horizontal
            case .horizontal: canvasModel.symmetryMode = .quadrant
            case .quadrant:   canvasModel.symmetryMode = .off
            }
            needsDisplay = true
        case "p":
            toolManager.selectTool(toolManager.penTool)
            toolManager.currentBrushPreset = .defaultPencil
        case "n":
            toolManager.selectTool(toolManager.penTool)
            toolManager.currentBrushPreset = .defaultSpray
        case "k":
            toolManager.selectTool(toolManager.penTool)
            toolManager.currentBrushPreset = .defaultMarker
        case "d":
            toolManager.selectTool(toolManager.penTool)
            toolManager.currentBrushPreset = .defaultSoftRound
        case "f":
            toolManager.selectTool(toolManager.penTool)
            toolManager.currentBrushPreset = .defaultDryBrush
        case "j":
            toolManager.selectTool(toolManager.penTool)
            toolManager.currentBrushPreset = .defaultInkSplatter
        case "r":
            toolManager.selectTool(toolManager.penTool)
            toolManager.currentBrushPreset = .defaultCharcoal
        case "t":
            toolManager.selectTool(toolManager.textTool)
        case "[":
            toolManager.decreaseBrushSize()
        case "]":
            toolManager.increaseBrushSize()
        default:
            break
        }
        window?.invalidateCursorRects(for: self)
        NotificationCenter.default.post(name: .toolSettingsChanged, object: self)
    }

    // MARK: - Public API

    func fitCanvasToView() {
        canvasTransform.canvasCenter = CGPoint(x: canvasModel.canvasSize.width / 2,
                                                y: canvasModel.canvasSize.height / 2)
        canvasTransform.resetZoom(canvasSize: canvasModel.canvasSize, viewSize: bounds.size)
        needsDisplay = true
        NotificationCenter.default.post(name: .canvasTransformChanged, object: self)
    }

    func zoomTo100() {
        canvasTransform.canvasCenter = CGPoint(x: canvasModel.canvasSize.width / 2,
                                                y: canvasModel.canvasSize.height / 2)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let canvasPt = canvasTransform.viewToCanvas(center)
        canvasTransform.scale = 1.0
        // Recompute offset so canvasPt maps to view center
        let viewAfter = canvasTransform.canvasToView(canvasPt)
        canvasTransform.offset.x += center.x - viewAfter.x
        canvasTransform.offset.y += center.y - viewAfter.y
        needsDisplay = true
        NotificationCenter.default.post(name: .canvasTransformChanged, object: self)
    }

    func resetRotation() {
        canvasTransform.rotation = 0
        needsDisplay = true
        NotificationCenter.default.post(name: .canvasTransformChanged, object: self)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let canvasTransformChanged = Notification.Name("canvasTransformChanged")
    static let toolSettingsChanged = Notification.Name("toolSettingsChanged")
}
