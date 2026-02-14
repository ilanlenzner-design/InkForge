import AppKit

enum SelectionShape: String {
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case lasso = "Lasso"
    case wand = "Wand"
}

class SelectionTool: Tool {
    let name = "Select"
    var cursor: NSCursor { .crosshair }

    var shape: SelectionShape = .rectangle

    private var dragOrigin: CGPoint?
    private var dragCurrent: CGPoint?
    private var lassoPoints: [CGPoint] = []
    private let wandTolerance: Int = 32

    func mouseDown(event: NSEvent, canvas: CanvasView) {
        let viewPoint = canvas.convert(event.locationInWindow, from: nil)
        let canvasPoint = canvas.canvasPoint(from: viewPoint)

        let mode = selectionMode(from: event)

        switch shape {
        case .rectangle, .ellipse:
            dragOrigin = canvasPoint
            dragCurrent = canvasPoint
        case .lasso:
            lassoPoints = [canvasPoint]
        case .wand:
            performMagicWand(at: canvasPoint, canvas: canvas, mode: mode)
        }
    }

    func mouseDragged(event: NSEvent, canvas: CanvasView) {
        let viewPoint = canvas.convert(event.locationInWindow, from: nil)
        let canvasPoint = canvas.canvasPoint(from: viewPoint)

        switch shape {
        case .rectangle, .ellipse:
            dragCurrent = canvasPoint
        case .lasso:
            lassoPoints.append(canvasPoint)
        case .wand:
            break
        }

        canvas.needsDisplay = true
    }

    func mouseUp(event: NSEvent, canvas: CanvasView) {
        let mode = selectionMode(from: event)
        let mask = canvas.canvasModel.ensureSelectionMask()

        switch shape {
        case .rectangle:
            guard let origin = dragOrigin, let current = dragCurrent else { break }
            let rect = rectFrom(origin, current)
            if rect.width > 1 && rect.height > 1 {
                mask.selectRect(rect, mode: mode)
            }

        case .ellipse:
            guard let origin = dragOrigin, let current = dragCurrent else { break }
            let rect = rectFrom(origin, current)
            if rect.width > 1 && rect.height > 1 {
                mask.selectEllipse(rect, mode: mode)
            }

        case .lasso:
            if lassoPoints.count >= 3 {
                mask.selectPolygon(lassoPoints, mode: mode)
            }

        case .wand:
            break  // handled in mouseDown
        }

        dragOrigin = nil
        dragCurrent = nil
        lassoPoints.removeAll()

        canvas.updateSelectionDisplay()
        canvas.needsDisplay = true
    }

    func drawOverlay(in ctx: CGContext, canvas: CanvasView) {
        let lineWidth = 1.0 / canvas.canvasTransform.scale
        let dashLen = 4.0 / canvas.canvasTransform.scale

        ctx.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineDash(phase: 0, lengths: [dashLen, dashLen])

        switch shape {
        case .rectangle:
            guard let origin = dragOrigin, let current = dragCurrent else { return }
            ctx.stroke(rectFrom(origin, current))

        case .ellipse:
            guard let origin = dragOrigin, let current = dragCurrent else { return }
            ctx.strokeEllipse(in: rectFrom(origin, current))

        case .lasso:
            guard lassoPoints.count >= 2 else { return }
            ctx.beginPath()
            ctx.move(to: lassoPoints[0])
            for i in 1..<lassoPoints.count {
                ctx.addLine(to: lassoPoints[i])
            }
            ctx.strokePath()

        case .wand:
            break
        }

        // Reset dash
        ctx.setLineDash(phase: 0, lengths: [])
    }

    func handleKeyDown(event: NSEvent, canvas: CanvasView) -> Bool {
        return false
    }

    // MARK: - Helpers

    private func selectionMode(from event: NSEvent) -> SelectionMode {
        let mods = event.modifierFlags
        if mods.contains(.shift) { return .add }
        if mods.contains(.option) { return .subtract }
        return .new
    }

    private func rectFrom(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                      width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func performMagicWand(at point: CGPoint, canvas: CanvasView, mode: SelectionMode) {
        let w = Int(canvas.canvasModel.canvasSize.width)
        let h = Int(canvas.canvasModel.canvasSize.height)

        guard let compositeImage = canvas.canvasModel.layerStack.compositeImage(),
              let compCtx = CGContext(
                  data: nil, width: w, height: h,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return }

        compCtx.draw(compositeImage, in: CGRect(origin: .zero, size: canvas.canvasModel.canvasSize))

        guard let data = compCtx.data else { return }
        let bytesPerRow = compCtx.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: h * bytesPerRow)

        let mask = canvas.canvasModel.ensureSelectionMask()
        mask.magicWand(at: point, compositeData: pixels, bytesPerRow: bytesPerRow,
                       tolerance: wandTolerance, mode: mode)

        canvas.updateSelectionDisplay()
        canvas.needsDisplay = true
    }
}
