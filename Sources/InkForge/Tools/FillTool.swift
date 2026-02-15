import AppKit

class FillTool: Tool {
    let name = "Fill"

    var cursor: NSCursor {
        let img = Self.makePaintBucketCursor()
        // Hot spot at the paint pour tip (bottom-left origin: y=5 is near bottom of 24px image)
        return NSCursor(image: img, hotSpot: NSPoint(x: 17, y: 5))
    }

    private let tolerance: Int = 32

    func mouseDown(event: NSEvent, canvas: CanvasView) {
        guard let layer = canvas.canvasModel.layerStack.activeLayer,
              !layer.isLocked, !layer.isTextLayer else { return }

        canvas.canvasModel.snapshotActiveLayerForUndo()

        let viewPoint = canvas.convert(event.locationInWindow, from: nil)
        let canvasPoint = canvas.canvasPoint(from: viewPoint)

        let width = Int(layer.size.width)
        let height = Int(layer.size.height)

        // Convert canvas coords to pixel data indices.
        // CGBitmapContext stores pixel data top-to-bottom in memory (row 0 = top of image).
        // Canvas coords are also top-to-bottom (isFlipped view). So no Y flip is needed.
        let pixelX = Int(canvasPoint.x)
        let pixelY = Int(canvasPoint.y)

        guard pixelX >= 0, pixelX < width, pixelY >= 0, pixelY < height else { return }

        let sel = canvas.canvasModel.selectionMask

        // Check if click is within selection (if selection exists)
        if let sel = sel, !sel.isEmpty, !sel.isSelected(x: pixelX, y: pixelY) { return }

        // Use reference layer for boundary detection if one is set, otherwise active layer.
        let refImage: CGImage?
        if let refLayer = canvas.canvasModel.layerStack.referenceLayer {
            refImage = refLayer.makeImage()
        } else {
            refImage = layer.makeImage()
        }

        guard let compositeImage = refImage,
              let compositeCG = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return }

        compositeCG.draw(compositeImage, in: CGRect(origin: .zero, size: layer.size))

        guard let compositeData = compositeCG.data else { return }
        let refBytesPerRow = compositeCG.bytesPerRow
        let refPixels = compositeData.bindMemory(to: UInt8.self, capacity: height * refBytesPerRow)

        // Get target color from composite at click point
        let targetOffset = pixelY * refBytesPerRow + pixelX * 4
        let targetR = refPixels[targetOffset]
        let targetG = refPixels[targetOffset + 1]
        let targetB = refPixels[targetOffset + 2]
        let targetA = refPixels[targetOffset + 3]

        // Prepare fill color
        let fillColor = canvas.toolManager!.currentColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        fillColor.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)

        let fillR = UInt8(r * 255)
        let fillG = UInt8(g * 255)
        let fillB = UInt8(b * 255)
        let fillA = UInt8(a * 255)

        // Check if composite color at click is already the fill color
        if targetR == fillR && targetG == fillG && targetB == fillB && targetA == fillA {
            return
        }

        // Fill into the ACTIVE layer's drawing context (content or mask)
        let drawCtx = layer.drawingContext
        guard let layerData = drawCtx.data else { return }
        let layerBytesPerRow = drawCtx.bytesPerRow
        let layerPixels = layerData.bindMemory(to: UInt8.self, capacity: height * layerBytesPerRow)
        let isMask = layer.isMaskEditing

        // For mask editing: fill with grayscale luminance (1 byte/pixel)
        let fillGray = UInt8(CGFloat(fillR) * 0.299 + CGFloat(fillG) * 0.587 + CGFloat(fillB) * 0.114)

        floodFill(at: canvasPoint, width: width, height: height,
                  refPixels: refPixels, refBytesPerRow: refBytesPerRow,
                  layerPixels: layerPixels, layerBytesPerRow: layerBytesPerRow,
                  targetR: targetR, targetG: targetG, targetB: targetB, targetA: targetA,
                  fillR: fillR, fillG: fillG, fillB: fillB, fillA: fillA,
                  fillGray: fillGray, isMask: isMask, selection: sel)

        // Symmetry: fill at mirrored click points
        let sym = canvas.canvasModel.symmetryMode
        if sym != .off {
            let mirrorPts = symmetryMirrorPoints(canvasPoint, mode: sym,
                    axisX: canvas.canvasModel.effectiveSymmetryAxisX,
                    axisY: canvas.canvasModel.effectiveSymmetryAxisY)
            for mp in mirrorPts {
                floodFill(at: mp, width: width, height: height,
                          refPixels: refPixels, refBytesPerRow: refBytesPerRow,
                          layerPixels: layerPixels, layerBytesPerRow: layerBytesPerRow,
                          targetR: targetR, targetG: targetG, targetB: targetB, targetA: targetA,
                          fillR: fillR, fillG: fillG, fillB: fillB, fillA: fillA,
                          fillGray: fillGray, isMask: isMask, selection: sel)
            }
        }

        canvas.compositeDirty = true
        canvas.needsDisplay = true

        canvas.canvasModel.registerUndoForActiveLayer(actionName: "Fill")
    }

    func mouseDragged(event: NSEvent, canvas: CanvasView) {}

    func mouseUp(event: NSEvent, canvas: CanvasView) {}

    private func floodFill(at point: CGPoint, width: Int, height: Int,
                           refPixels: UnsafeMutablePointer<UInt8>, refBytesPerRow: Int,
                           layerPixels: UnsafeMutablePointer<UInt8>, layerBytesPerRow: Int,
                           targetR: UInt8, targetG: UInt8, targetB: UInt8, targetA: UInt8,
                           fillR: UInt8, fillG: UInt8, fillB: UInt8, fillA: UInt8,
                           fillGray: UInt8 = 255, isMask: Bool = false,
                           selection: SelectionMask?) {
        let pixelX = Int(point.x)
        let pixelY = Int(point.y)
        guard pixelX >= 0, pixelX < width, pixelY >= 0, pixelY < height else { return }

        // Check selection
        if let sel = selection, !sel.isEmpty, !sel.isSelected(x: pixelX, y: pixelY) { return }

        // Verify target color matches at this mirrored point too
        let checkOff = pixelY * refBytesPerRow + pixelX * 4
        if !colorMatches(refPixels[checkOff], refPixels[checkOff+1], refPixels[checkOff+2], refPixels[checkOff+3],
                         targetR, targetG, targetB, targetA) { return }

        var visited = [Bool](repeating: false, count: width * height)
        var stack: [(Int, Int)] = [(pixelX, pixelY)]
        visited[pixelY * width + pixelX] = true

        while !stack.isEmpty {
            let (sx, sy) = stack.removeLast()

            var left = sx
            while left > 0 {
                let idx = sy * width + (left - 1)
                if visited[idx] { break }
                let off = sy * refBytesPerRow + (left - 1) * 4
                if !colorMatches(refPixels[off], refPixels[off+1], refPixels[off+2], refPixels[off+3],
                                 targetR, targetG, targetB, targetA) { break }
                left -= 1
            }

            var right = sx
            while right < width - 1 {
                let idx = sy * width + (right + 1)
                if visited[idx] { break }
                let off = sy * refBytesPerRow + (right + 1) * 4
                if !colorMatches(refPixels[off], refPixels[off+1], refPixels[off+2], refPixels[off+3],
                                 targetR, targetG, targetB, targetA) { break }
                right += 1
            }

            var aboveAdded = false
            var belowAdded = false

            for x in left...right {
                let idx = sy * width + x
                visited[idx] = true

                if let sel = selection, !sel.isEmpty, !sel.isSelected(x: x, y: sy) { continue }

                if isMask {
                    let lOff = sy * layerBytesPerRow + x
                    layerPixels[lOff] = fillGray
                } else {
                    let lOff = sy * layerBytesPerRow + x * 4
                    layerPixels[lOff]     = fillR
                    layerPixels[lOff + 1] = fillG
                    layerPixels[lOff + 2] = fillB
                    layerPixels[lOff + 3] = fillA
                }

                if sy > 0 {
                    let aboveIdx = (sy - 1) * width + x
                    if !visited[aboveIdx] {
                        let aOff = (sy - 1) * refBytesPerRow + x * 4
                        let matches = colorMatches(refPixels[aOff], refPixels[aOff+1], refPixels[aOff+2], refPixels[aOff+3],
                                                   targetR, targetG, targetB, targetA)
                        if matches && !aboveAdded {
                            stack.append((x, sy - 1))
                            aboveAdded = true
                        }
                        if !matches { aboveAdded = false }
                    }
                }

                if sy < height - 1 {
                    let belowIdx = (sy + 1) * width + x
                    if !visited[belowIdx] {
                        let bOff = (sy + 1) * refBytesPerRow + x * 4
                        let matches = colorMatches(refPixels[bOff], refPixels[bOff+1], refPixels[bOff+2], refPixels[bOff+3],
                                                   targetR, targetG, targetB, targetA)
                        if matches && !belowAdded {
                            stack.append((x, sy + 1))
                            belowAdded = true
                        }
                        if !matches { belowAdded = false }
                    }
                }
            }
        }
    }

    private func colorMatches(_ r1: UInt8, _ g1: UInt8, _ b1: UInt8, _ a1: UInt8,
                              _ r2: UInt8, _ g2: UInt8, _ b2: UInt8, _ a2: UInt8) -> Bool {
        return abs(Int(r1) - Int(r2)) <= tolerance &&
               abs(Int(g1) - Int(g2)) <= tolerance &&
               abs(Int(b1) - Int(b2)) <= tolerance &&
               abs(Int(a1) - Int(a2)) <= tolerance
    }

    // MARK: - Paint Bucket Cursor

    private static func makePaintBucketCursor() -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 24))
        image.lockFocus()

        NSColor.black.setFill()
        NSColor.black.setStroke()

        // Tilted bucket body
        let body = NSBezierPath()
        body.move(to: NSPoint(x: 3, y: 14))
        body.line(to: NSPoint(x: 15, y: 14))
        body.line(to: NSPoint(x: 13, y: 4))
        body.line(to: NSPoint(x: 5, y: 4))
        body.close()
        body.fill()

        // Rim
        let rim = NSBezierPath()
        rim.move(to: NSPoint(x: 2, y: 14.5))
        rim.line(to: NSPoint(x: 16, y: 14.5))
        rim.lineWidth = 2.0
        rim.lineCapStyle = .round
        rim.stroke()

        // Handle
        let handle = NSBezierPath()
        handle.appendArc(withCenter: NSPoint(x: 9, y: 14.5),
                         radius: 4,
                         startAngle: 0,
                         endAngle: 180)
        handle.lineWidth = 1.5
        handle.lineCapStyle = .round
        handle.stroke()

        // Paint drop
        let drop = NSBezierPath(ovalIn: NSRect(x: 15, y: 5, width: 5, height: 7))
        drop.fill()

        // White outline for visibility on dark backgrounds
        NSColor.white.setStroke()
        let outline = NSBezierPath()
        outline.move(to: NSPoint(x: 2, y: 15.5))
        outline.line(to: NSPoint(x: 16, y: 15.5))
        outline.lineWidth = 0.5
        outline.stroke()

        image.unlockFocus()
        return image
    }
}
