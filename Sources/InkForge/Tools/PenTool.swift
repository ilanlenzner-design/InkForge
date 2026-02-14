import AppKit

class PenTool: Tool {
    let name = "Pen"
    var cursor: NSCursor { .crosshair }

    private var currentStroke: StrokeData?
    private var smoother: StrokeSmoother?
    private var shapeHoldTimer: Timer?
    private var shapeDetected: DetectedShape?

    func mouseDown(event: NSEvent, canvas: CanvasView) {
        guard let layer = canvas.canvasModel.layerStack.activeLayer,
              !layer.isLocked, !layer.isTextLayer else { return }

        let mgr = canvas.toolManager!
        let stroke = StrokeData(brushPreset: mgr.currentBrushPreset,
                                 color: mgr.currentColor,
                                 layerIndex: canvas.canvasModel.layerStack.activeLayerIndex)

        smoother = StrokeSmoother(amount: mgr.currentBrushPreset.streamLine)

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

    func mouseDraggedForShape(event: NSEvent, canvas: CanvasView) {
        // Reset shape hold timer on each drag
        shapeHoldTimer?.invalidate()
        shapeHoldTimer = nil
        shapeDetected = nil
    }

    func mouseUp(event: NSEvent, canvas: CanvasView) {
        shapeHoldTimer?.invalidate()
        shapeHoldTimer = nil

        guard let stroke = currentStroke else { return }

        let point = makeStrokePoint(from: event, canvas: canvas)
        stroke.addPoint(point)

        guard let layer = canvas.canvasModel.layerStack.activeLayer else { return }
        let sel = canvas.canvasModel.selectionMask

        // QuickShape: check if pen was held still at end (last drag > 0.3s ago)
        let points = stroke.points.map { $0.location }
        if points.count > 2 {
            let lastTwo = stroke.points.suffix(2)
            let timeDiff = lastTwo.last!.timestamp - lastTwo.first!.timestamp
            if timeDiff > 0.3, let shape = ShapeDetector.detect(from: points) {
                // Render clean shape instead of freehand
                layer.beginDrawing(clippingTo: sel)
                renderShape(shape, stroke: stroke, into: layer.drawingContext)
                let sym = canvas.canvasModel.symmetryMode
                if sym != .off {
                    for mirrorStroke in stroke.symmetryMirrors(mode: sym,
                            axisX: canvas.canvasModel.effectiveSymmetryAxisX,
                            axisY: canvas.canvasModel.effectiveSymmetryAxisY) {
                        let mirrorPts = mirrorStroke.points.map { $0.location }
                        if let mirrorShape = ShapeDetector.detect(from: mirrorPts) {
                            renderShape(mirrorShape, stroke: mirrorStroke, into: layer.drawingContext)
                        } else {
                            StrokeRenderer().renderStroke(mirrorStroke, into: layer.drawingContext)
                        }
                    }
                }
                layer.endDrawing()

                currentStroke = nil
                canvas.currentStroke = nil
                smoother = nil
                canvas.compositeDirty = true
                canvas.needsDisplay = true
                canvas.canvasModel.registerUndoForActiveLayer(actionName: "Draw Shape")
                return
            }
        }

        let renderer = StrokeRenderer()
        layer.beginDrawing(clippingTo: sel)
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

        canvas.canvasModel.registerUndoForActiveLayer(actionName: "Draw Stroke")
    }

    private func renderShape(_ shape: DetectedShape, stroke: StrokeData, into ctx: CGContext) {
        let color = stroke.color
        let lineWidth = stroke.brushPreset.maxRadius * 2

        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch shape.kind {
        case .line(let from, let to):
            ctx.move(to: from)
            ctx.addLine(to: to)
            ctx.strokePath()

        case .ellipse(let center, let rx, let ry):
            let rect = CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)
            ctx.strokeEllipse(in: rect)

        case .rectangle(let rect):
            ctx.stroke(rect)
        }
    }

    private func makeStrokePoint(from event: NSEvent, canvas: CanvasView) -> StrokePoint {
        let viewPoint = canvas.convert(event.locationInWindow, from: nil)
        var canvasPoint = canvas.canvasPoint(from: viewPoint)

        if let smoother = smoother {
            canvasPoint = smoother.smooth(canvasPoint)
        }

        let pressure: CGFloat
        let tilt: NSPoint
        let rotation: CGFloat

        if event.subtype == .tabletPoint {
            pressure = CGFloat(event.pressure)
            tilt = event.tilt
            rotation = CGFloat(event.rotation)
        } else {
            pressure = 1.0
            tilt = .zero
            rotation = 0
        }

        return StrokePoint(
            location: canvasPoint,
            pressure: pressure,
            tiltX: tilt.x,
            tiltY: tilt.y,
            rotation: rotation,
            timestamp: event.timestamp
        )
    }
}
