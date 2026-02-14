import AppKit

class SmudgeTool: Tool {
    let name = "Smudge"
    var cursor: NSCursor { .crosshair }

    private var lastCanvasPoint: CGPoint?
    private var strength: CGFloat = 0.5

    func mouseDown(event: NSEvent, canvas: CanvasView) {
        guard let layer = canvas.canvasModel.layerStack.activeLayer,
              !layer.isLocked, !layer.isTextLayer else { return }

        canvas.canvasModel.snapshotActiveLayerForUndo()

        let viewPoint = canvas.convert(event.locationInWindow, from: nil)
        let canvasPoint = canvas.canvasPoint(from: viewPoint)
        lastCanvasPoint = canvasPoint
    }

    func mouseDragged(event: NSEvent, canvas: CanvasView) {
        guard let layer = canvas.canvasModel.layerStack.activeLayer,
              let lastPt = lastCanvasPoint else { return }

        let viewPoint = canvas.convert(event.locationInWindow, from: nil)
        let canvasPoint = canvas.canvasPoint(from: viewPoint)

        // Delta in canvas coordinates (top-left origin, Y increases downward)
        let dxCanvas = canvasPoint.x - lastPt.x
        let dyCanvas = canvasPoint.y - lastPt.y

        // Skip if barely moved
        guard abs(dxCanvas) > 0.5 || abs(dyCanvas) > 0.5 else { return }

        let pressure: CGFloat = event.subtype == .tabletPoint ? CGFloat(event.pressure) : 1.0
        let alpha = strength * pressure

        let drawCtx = layer.drawingContext
        guard let data = drawCtx.data else { return }

        let width = Int(layer.size.width)
        let height = Int(layer.size.height)
        let bytesPerRow = drawCtx.bytesPerRow
        let isMask = layer.isMaskEditing
        let bufSize = isMask ? height * bytesPerRow : width * height * 4
        let pixels = data.bindMemory(to: UInt8.self, capacity: bufSize)

        let radius = canvas.toolManager!.currentBrushPreset.maxRadius
        let sel = canvas.canvasModel.selectionMask

        smudgeCircle(centerX: canvasPoint.x, centerY: canvasPoint.y,
                     dx: dxCanvas, dy: dyCanvas, radius: radius, alpha: alpha,
                     pixels: pixels, width: width, height: height,
                     bytesPerRow: bytesPerRow, isAlphaLocked: layer.isAlphaLocked,
                     isMask: isMask, selection: sel)

        // Symmetry: smudge at mirrored positions with mirrored deltas
        let sym = canvas.canvasModel.symmetryMode
        if sym != .off {
            let axisX = canvas.canvasModel.effectiveSymmetryAxisX
            let axisY = canvas.canvasModel.effectiveSymmetryAxisY

            switch sym {
            case .off: break
            case .vertical:
                smudgeCircle(centerX: 2 * axisX - canvasPoint.x, centerY: canvasPoint.y,
                             dx: -dxCanvas, dy: dyCanvas, radius: radius, alpha: alpha,
                             pixels: pixels, width: width, height: height,
                             bytesPerRow: bytesPerRow, isAlphaLocked: layer.isAlphaLocked,
                             isMask: isMask, selection: sel)
            case .horizontal:
                smudgeCircle(centerX: canvasPoint.x, centerY: 2 * axisY - canvasPoint.y,
                             dx: dxCanvas, dy: -dyCanvas, radius: radius, alpha: alpha,
                             pixels: pixels, width: width, height: height,
                             bytesPerRow: bytesPerRow, isAlphaLocked: layer.isAlphaLocked,
                             isMask: isMask, selection: sel)
            case .quadrant:
                smudgeCircle(centerX: 2 * axisX - canvasPoint.x, centerY: canvasPoint.y,
                             dx: -dxCanvas, dy: dyCanvas, radius: radius, alpha: alpha,
                             pixels: pixels, width: width, height: height,
                             bytesPerRow: bytesPerRow, isAlphaLocked: layer.isAlphaLocked,
                             isMask: isMask, selection: sel)
                smudgeCircle(centerX: canvasPoint.x, centerY: 2 * axisY - canvasPoint.y,
                             dx: dxCanvas, dy: -dyCanvas, radius: radius, alpha: alpha,
                             pixels: pixels, width: width, height: height,
                             bytesPerRow: bytesPerRow, isAlphaLocked: layer.isAlphaLocked,
                             isMask: isMask, selection: sel)
                smudgeCircle(centerX: 2 * axisX - canvasPoint.x, centerY: 2 * axisY - canvasPoint.y,
                             dx: -dxCanvas, dy: -dyCanvas, radius: radius, alpha: alpha,
                             pixels: pixels, width: width, height: height,
                             bytesPerRow: bytesPerRow, isAlphaLocked: layer.isAlphaLocked,
                             isMask: isMask, selection: sel)
            }
        }

        lastCanvasPoint = canvasPoint

        canvas.compositeDirty = true
        canvas.needsDisplay = true
    }

    private func smudgeCircle(centerX: CGFloat, centerY: CGFloat,
                              dx: CGFloat, dy: CGFloat,
                              radius: CGFloat, alpha: CGFloat,
                              pixels: UnsafeMutablePointer<UInt8>,
                              width: Int, height: Int, bytesPerRow: Int,
                              isAlphaLocked: Bool, isMask: Bool = false,
                              selection: SelectionMask?) {
        let radiusSq = radius * radius
        let centerPxX = Int(centerX)
        let centerPxY = Int(centerY)
        let dxPx = Int(round(dx))
        let dyPx = Int(round(dy))
        let intRadius = Int(radius)

        for oy in -intRadius...intRadius {
            for ox in -intRadius...intRadius {
                let distSq = CGFloat(ox * ox + oy * oy)
                if distSq > radiusSq { continue }

                let falloff = 1.0 - (distSq / radiusSq)
                let pixelAlpha = alpha * falloff

                let dstX = centerPxX + ox
                let dstY = centerPxY + oy
                let srcX = dstX - dxPx
                let srcY = dstY - dyPx

                guard dstX >= 0, dstX < width, dstY >= 0, dstY < height,
                      srcX >= 0, srcX < width, srcY >= 0, srcY < height else { continue }

                if let sel = selection, !sel.isEmpty,
                   !sel.isSelected(x: dstX, y: dstY) { continue }

                if isMask {
                    // Grayscale: 1 byte per pixel
                    let srcOff = srcY * bytesPerRow + srcX
                    let dstOff = dstY * bytesPerRow + dstX
                    let srcV = CGFloat(pixels[srcOff])
                    let dstV = CGFloat(pixels[dstOff])
                    pixels[dstOff] = UInt8(dstV + (srcV - dstV) * pixelAlpha)
                } else {
                    let srcOff = srcY * bytesPerRow + srcX * 4
                    let dstOff = dstY * bytesPerRow + dstX * 4

                    let srcR = CGFloat(pixels[srcOff])
                    let srcG = CGFloat(pixels[srcOff + 1])
                    let srcB = CGFloat(pixels[srcOff + 2])
                    let srcA = CGFloat(pixels[srcOff + 3])

                    let dstR = CGFloat(pixels[dstOff])
                    let dstG = CGFloat(pixels[dstOff + 1])
                    let dstB = CGFloat(pixels[dstOff + 2])
                    let dstA = CGFloat(pixels[dstOff + 3])

                    pixels[dstOff]     = UInt8(dstR + (srcR - dstR) * pixelAlpha)
                    pixels[dstOff + 1] = UInt8(dstG + (srcG - dstG) * pixelAlpha)
                    pixels[dstOff + 2] = UInt8(dstB + (srcB - dstB) * pixelAlpha)
                    if !isAlphaLocked {
                        pixels[dstOff + 3] = UInt8(dstA + (srcA - dstA) * pixelAlpha)
                    }
                }
            }
        }
    }

    func mouseUp(event: NSEvent, canvas: CanvasView) {
        lastCanvasPoint = nil
        canvas.canvasModel.registerUndoForActiveLayer(actionName: "Smudge")
    }
}
