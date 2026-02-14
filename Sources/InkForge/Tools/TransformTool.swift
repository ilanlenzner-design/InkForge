import AppKit

class TransformTool: Tool {
    let name = "Transform"
    var cursor: NSCursor { .openHand }

    private(set) var isActive = false
    private(set) var extractedImage: CGImage?
    private(set) var originalBounds: CGRect = .zero

    // Transform state
    private(set) var offset: CGPoint = .zero
    private(set) var scaleX: CGFloat = 1.0
    private(set) var scaleY: CGFloat = 1.0

    // Text layer transform: stored original content for commit
    private var originalTextContent: TextContent?

    private enum HandleType { case move, topLeft, topRight, bottomLeft, bottomRight }
    private var dragStart: CGPoint?
    private var dragHandle: HandleType?
    private var initialOffset: CGPoint = .zero
    private var initialScaleX: CGFloat = 1.0
    private var initialScaleY: CGFloat = 1.0

    var transformedBounds: CGRect {
        CGRect(x: originalBounds.minX + offset.x,
               y: originalBounds.minY + offset.y,
               width: originalBounds.width * scaleX,
               height: originalBounds.height * scaleY)
    }

    // MARK: - Activation

    func activate(canvas: CanvasView) {
        guard !isActive else { return }
        let model = canvas.canvasModel!
        guard let layer = model.layerStack.activeLayer, !layer.isLocked else { return }

        let mask = model.selectionMask
        let bounds: CGRect

        if layer.isTextLayer, let tc = layer.textContent {
            // Text layer: use tight text bounding rect
            originalTextContent = tc
            bounds = tc.boundingRect()
        } else if let m = mask, !m.isEmpty, let sb = m.bounds {
            originalTextContent = nil
            bounds = sb
        } else {
            originalTextContent = nil
            bounds = CGRect(origin: .zero, size: model.canvasSize)
        }

        originalBounds = bounds
        model.snapshotActiveLayerForUndo()

        extractedImage = extractPixels(from: layer, in: bounds, mask: mask)
        clearPixels(in: layer, bounds: bounds, mask: mask)

        offset = .zero
        scaleX = 1.0
        scaleY = 1.0
        isActive = true

        canvas.compositeDirty = true
        canvas.needsDisplay = true
    }

    func commit(canvas: CanvasView) {
        guard isActive, let image = extractedImage else { return }
        guard let layer = canvas.canvasModel.layerStack.activeLayer else { return }

        if let tc = originalTextContent {
            // Text layer: update position and font size, re-render crisp text
            let avgScale = (scaleX + scaleY) / 2.0
            let newContent = TextContent(
                text: tc.text,
                fontName: tc.fontName,
                fontSize: tc.fontSize * avgScale,
                isBold: tc.isBold,
                isItalic: tc.isItalic,
                color: tc.color,
                position: CGPoint(x: tc.position.x + offset.x,
                                  y: tc.position.y + offset.y)
            )
            layer.textContent = newContent
        } else {
            // Pixel layer: draw extracted image at new position/scale
            let dest = transformedBounds
            layer.beginDrawing()
            layer.context.saveGState()
            layer.context.translateBy(x: dest.minX, y: dest.minY + dest.height)
            layer.context.scaleBy(x: 1, y: -1)
            layer.context.draw(image, in: CGRect(origin: .zero, size: dest.size))
            layer.context.restoreGState()
            layer.endDrawing()
        }

        canvas.canvasModel.registerUndoForActiveLayer(actionName: "Transform")

        cleanup()
        canvas.compositeDirty = true
        canvas.needsDisplay = true
    }

    func cancel(canvas: CanvasView) {
        guard isActive else { return }
        canvas.canvasModel.undo()
        cleanup()
        canvas.compositeDirty = true
        canvas.needsDisplay = true
    }

    private func cleanup() {
        isActive = false
        extractedImage = nil
        originalTextContent = nil
        dragStart = nil
        dragHandle = nil
    }

    // MARK: - Tool Protocol

    func mouseDown(event: NSEvent, canvas: CanvasView) {
        if !isActive {
            activate(canvas: canvas)
            return
        }

        let viewPoint = canvas.convert(event.locationInWindow, from: nil)
        let cp = canvas.canvasPoint(from: viewPoint)
        let dest = transformedBounds
        let hs = 12 / canvas.canvasTransform.scale

        // Check corner handles
        let corners: [(CGPoint, HandleType)] = [
            (CGPoint(x: dest.minX, y: dest.minY), .topLeft),
            (CGPoint(x: dest.maxX, y: dest.minY), .topRight),
            (CGPoint(x: dest.minX, y: dest.maxY), .bottomLeft),
            (CGPoint(x: dest.maxX, y: dest.maxY), .bottomRight),
        ]

        for (pt, handle) in corners {
            if CGRect(x: pt.x - hs/2, y: pt.y - hs/2, width: hs, height: hs).contains(cp) {
                dragHandle = handle
                dragStart = cp
                initialOffset = offset
                initialScaleX = scaleX
                initialScaleY = scaleY
                return
            }
        }

        // Inside box = move
        if dest.contains(cp) {
            dragHandle = .move
            dragStart = cp
            initialOffset = offset
            return
        }

        // Outside = commit and start fresh
        commit(canvas: canvas)
    }

    func mouseDragged(event: NSEvent, canvas: CanvasView) {
        guard isActive, let start = dragStart, let handle = dragHandle else { return }

        let viewPoint = canvas.convert(event.locationInWindow, from: nil)
        let cp = canvas.canvasPoint(from: viewPoint)
        let dx = cp.x - start.x
        let dy = cp.y - start.y

        switch handle {
        case .move:
            offset = CGPoint(x: initialOffset.x + dx, y: initialOffset.y + dy)

        case .bottomRight:
            let newW = originalBounds.width * initialScaleX + dx
            let newH = originalBounds.height * initialScaleY + dy
            if event.modifierFlags.contains(.shift) {
                let avg = ((newW / originalBounds.width) + (newH / originalBounds.height)) / 2
                scaleX = max(0.05, avg)
                scaleY = max(0.05, avg)
            } else {
                scaleX = max(0.05, newW / originalBounds.width)
                scaleY = max(0.05, newH / originalBounds.height)
            }

        case .topLeft:
            let newW = originalBounds.width * initialScaleX - dx
            let newH = originalBounds.height * initialScaleY - dy
            scaleX = max(0.05, newW / originalBounds.width)
            scaleY = max(0.05, newH / originalBounds.height)
            offset = CGPoint(x: initialOffset.x + dx, y: initialOffset.y + dy)

        case .topRight:
            let newW = originalBounds.width * initialScaleX + dx
            let newH = originalBounds.height * initialScaleY - dy
            scaleX = max(0.05, newW / originalBounds.width)
            scaleY = max(0.05, newH / originalBounds.height)
            offset = CGPoint(x: initialOffset.x, y: initialOffset.y + dy)

        case .bottomLeft:
            let newW = originalBounds.width * initialScaleX - dx
            let newH = originalBounds.height * initialScaleY + dy
            scaleX = max(0.05, newW / originalBounds.width)
            scaleY = max(0.05, newH / originalBounds.height)
            offset = CGPoint(x: initialOffset.x + dx, y: initialOffset.y)
        }

        canvas.compositeDirty = true
        canvas.needsDisplay = true
    }

    func mouseUp(event: NSEvent, canvas: CanvasView) {
        dragStart = nil
        dragHandle = nil
    }

    func drawOverlay(in ctx: CGContext, canvas: CanvasView) {
        guard isActive, let image = extractedImage else { return }

        let dest = transformedBounds

        // Draw the floating image
        ctx.saveGState()
        ctx.translateBy(x: dest.minX, y: dest.minY + dest.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: dest.size))
        ctx.restoreGState()

        // Bounding box
        let lw = 1.5 / canvas.canvasTransform.scale
        ctx.setStrokeColor(NSColor.systemBlue.cgColor)
        ctx.setLineWidth(lw)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.stroke(dest)

        // Corner handles
        let hs: CGFloat = 8 / canvas.canvasTransform.scale
        let handles = [
            CGPoint(x: dest.minX, y: dest.minY),
            CGPoint(x: dest.maxX, y: dest.minY),
            CGPoint(x: dest.minX, y: dest.maxY),
            CGPoint(x: dest.maxX, y: dest.maxY),
        ]

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.setStrokeColor(NSColor.systemBlue.cgColor)
        ctx.setLineWidth(1.0 / canvas.canvasTransform.scale)

        for h in handles {
            let r = CGRect(x: h.x - hs/2, y: h.y - hs/2, width: hs, height: hs)
            ctx.fill(r)
            ctx.stroke(r)
        }
    }

    func handleKeyDown(event: NSEvent, canvas: CanvasView) -> Bool {
        guard isActive else { return false }

        switch event.keyCode {
        case 36: // Enter
            commit(canvas: canvas)
            return true
        case 53: // Escape
            cancel(canvas: canvas)
            return true
        default:
            return false
        }
    }

    // MARK: - Pixel Extraction

    private func extractPixels(from layer: Layer, in bounds: CGRect, mask: SelectionMask?) -> CGImage? {
        guard let srcData = layer.context.data else { return nil }
        let srcBPR = layer.context.bytesPerRow
        let srcPixels = srcData.bindMemory(to: UInt8.self, capacity: Int(layer.size.height) * srcBPR)

        let bx = Int(bounds.minX)
        let by = Int(bounds.minY)
        let bw = Int(bounds.width)
        let bh = Int(bounds.height)

        guard let dstCtx = CGContext(data: nil, width: bw, height: bh,
                                      bitsPerComponent: 8, bytesPerRow: bw * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let dstData = dstCtx.data else { return nil }

        let dstPixels = dstData.bindMemory(to: UInt8.self, capacity: bh * bw * 4)
        dstCtx.clear(CGRect(x: 0, y: 0, width: bw, height: bh))

        for y in 0..<bh {
            for x in 0..<bw {
                let sx = bx + x
                let sy = by + y
                if let mask = mask, !mask.isSelected(x: sx, y: sy) { continue }

                let srcOff = sy * srcBPR + sx * 4
                let dstOff = y * (bw * 4) + x * 4
                dstPixels[dstOff]     = srcPixels[srcOff]
                dstPixels[dstOff + 1] = srcPixels[srcOff + 1]
                dstPixels[dstOff + 2] = srcPixels[srcOff + 2]
                dstPixels[dstOff + 3] = srcPixels[srcOff + 3]
            }
        }

        return dstCtx.makeImage()
    }

    private func clearPixels(in layer: Layer, bounds: CGRect, mask: SelectionMask?) {
        guard let data = layer.context.data else { return }
        let bpr = layer.context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: Int(layer.size.height) * bpr)

        let bx = Int(bounds.minX)
        let by = Int(bounds.minY)
        let bw = Int(bounds.width)
        let bh = Int(bounds.height)

        for y in 0..<bh {
            for x in 0..<bw {
                let sx = bx + x
                let sy = by + y
                if let mask = mask, !mask.isSelected(x: sx, y: sy) { continue }

                let off = sy * bpr + sx * 4
                pixels[off] = 0
                pixels[off + 1] = 0
                pixels[off + 2] = 0
                pixels[off + 3] = 0
            }
        }
    }
}
