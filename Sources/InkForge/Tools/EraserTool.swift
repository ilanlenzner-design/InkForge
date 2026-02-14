import AppKit

class EraserTool: Tool {
    let name = "Eraser"
    var cursor: NSCursor {
        return NSCursor(image: eraserCursorImage(), hotSpot: NSPoint(x: 8, y: 8))
    }

    private var currentStroke: StrokeData?
    private var smoother: StrokeSmoother?

    func mouseDown(event: NSEvent, canvas: CanvasView) {
        guard let layer = canvas.canvasModel.layerStack.activeLayer,
              !layer.isLocked, !layer.isTextLayer else { return }

        let mgr = canvas.toolManager!
        var eraserPreset = BrushPreset.defaultEraser
        eraserPreset.maxRadius = mgr.currentBrushPreset.maxRadius

        smoother = StrokeSmoother(amount: eraserPreset.streamLine)

        let stroke = StrokeData(brushPreset: eraserPreset,
                                 color: .white,
                                 layerIndex: canvas.canvasModel.layerStack.activeLayerIndex)

        let point = makeStrokePoint(from: event, canvas: canvas)
        stroke.addPoint(point)

        currentStroke = stroke
        canvas.currentStroke = stroke

        canvas.canvasModel.snapshotActiveLayerForUndo()
    }

    func mouseDragged(event: NSEvent, canvas: CanvasView) {
        guard let stroke = currentStroke else { return }

        let point = makeStrokePoint(from: event, canvas: canvas)
        let prevPoint = stroke.points.last!
        stroke.addPoint(point)

        canvas.invalidateForNewSegment(from: prevPoint, to: point,
                                        maxRadius: stroke.brushPreset.maxRadius)
    }

    func mouseUp(event: NSEvent, canvas: CanvasView) {
        guard let stroke = currentStroke else { return }

        let point = makeStrokePoint(from: event, canvas: canvas)
        stroke.addPoint(point)

        guard let layer = canvas.canvasModel.layerStack.activeLayer else { return }
        let renderer = StrokeRenderer()
        layer.beginDrawing(clippingTo: canvas.canvasModel.selectionMask)
        renderer.renderStroke(stroke, into: layer.drawingContext)
        let sym = canvas.canvasModel.symmetryMode
        if sym != .off {
            for mirror in stroke.symmetryMirrors(mode: sym,
                    axisX: canvas.canvasModel.effectiveSymmetryAxisX,
                    axisY: canvas.canvasModel.effectiveSymmetryAxisY) {
                renderer.renderStroke(mirror, into: layer.drawingContext)
            }
        }
        layer.endDrawing()

        currentStroke = nil
        canvas.currentStroke = nil
        smoother = nil
        canvas.compositeDirty = true
        canvas.needsDisplay = true

        canvas.canvasModel.registerUndoForActiveLayer(actionName: "Erase")
    }

    private func makeStrokePoint(from event: NSEvent, canvas: CanvasView) -> StrokePoint {
        let viewPoint = canvas.convert(event.locationInWindow, from: nil)
        var canvasPoint = canvas.canvasPoint(from: viewPoint)

        if let smoother = smoother {
            canvasPoint = smoother.smooth(canvasPoint)
        }

        let pressure: CGFloat = event.subtype == .tabletPoint ? CGFloat(event.pressure) : 1.0
        let tilt: NSPoint = event.subtype == .tabletPoint ? event.tilt : .zero

        return StrokePoint(
            location: canvasPoint,
            pressure: pressure,
            tiltX: tilt.x,
            tiltY: tilt.y,
            rotation: 0,
            timestamp: event.timestamp
        )
    }

    private func eraserCursorImage() -> NSImage {
        let size: CGFloat = 16
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.white.setFill()
        NSColor.gray.setStroke()
        let path = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: size - 2, height: size - 2))
        path.lineWidth = 1
        path.fill()
        path.stroke()
        image.unlockFocus()
        return image
    }
}
