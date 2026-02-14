import AppKit

protocol TextToolSheetDelegate: AnyObject {
    func textToolDidRequestSheet()
}

class TextTool: Tool {
    let name = "Text"

    var cursor: NSCursor { .iBeam }

    // Preview state
    private(set) var previewText: String = ""
    private(set) var previewLocation: CGPoint = .zero
    private(set) var previewFont: NSFont = .systemFont(ofSize: 24)
    private(set) var previewColor: NSColor = .black
    private(set) var isEditing: Bool = false

    // Track the raw font name from the sheet (for round-tripping)
    private(set) var editingFontName: String = "Helvetica"
    private(set) var editingFontSize: CGFloat = 24
    private(set) var editingBold: Bool = false
    private(set) var editingItalic: Bool = false

    // Re-edit mode: non-nil when editing an existing text layer
    private(set) var editingExistingLayer: Layer?

    weak var sheetDelegate: TextToolSheetDelegate?

    func mouseDown(event: NSEvent, canvas: CanvasView) {
        let viewPoint = canvas.convert(event.locationInWindow, from: nil)
        let canvasPoint = canvas.canvasPoint(from: viewPoint)

        let activeLayer = canvas.canvasModel.layerStack.activeLayer

        if let layer = activeLayer, layer.isTextLayer, let tc = layer.textContent,
           tc.boundingRect().contains(canvasPoint) {
            // RE-EDIT MODE: clicked on existing text
            editingExistingLayer = layer
            previewLocation = tc.position
            previewColor = tc.color
            previewText = tc.text
            previewFont = tc.resolvedFont()
            editingFontName = tc.fontName
            editingFontSize = tc.fontSize
            editingBold = tc.isBold
            editingItalic = tc.isItalic

            canvas.canvasModel.snapshotActiveLayerForUndo()
            isEditing = true
            canvas.needsDisplay = true
            sheetDelegate?.textToolDidRequestSheet()
        } else {
            // CREATION MODE: new text layer
            editingExistingLayer = nil
            previewLocation = canvasPoint
            previewColor = canvas.toolManager?.currentColor ?? .black
            previewText = ""
            previewFont = .systemFont(ofSize: 24)
            editingFontName = "Helvetica"
            editingFontSize = 24
            editingBold = false
            editingItalic = false
            isEditing = true
            canvas.needsDisplay = true
            sheetDelegate?.textToolDidRequestSheet()
        }
    }

    func mouseDragged(event: NSEvent, canvas: CanvasView) {}

    func mouseUp(event: NSEvent, canvas: CanvasView) {}

    // MARK: - Overlay

    func drawOverlay(in ctx: CGContext, canvas: CanvasView) {
        // Draw crosshair at insertion point
        if isEditing {
            let x = previewLocation.x
            let y = previewLocation.y
            let len: CGFloat = 8 / canvas.canvasTransform.scale

            ctx.saveGState()
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(2 / canvas.canvasTransform.scale)
            ctx.move(to: CGPoint(x: x - len, y: y))
            ctx.addLine(to: CGPoint(x: x + len, y: y))
            ctx.move(to: CGPoint(x: x, y: y - len))
            ctx.addLine(to: CGPoint(x: x, y: y + len))
            ctx.strokePath()

            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1 / canvas.canvasTransform.scale)
            ctx.move(to: CGPoint(x: x - len, y: y))
            ctx.addLine(to: CGPoint(x: x + len, y: y))
            ctx.move(to: CGPoint(x: x, y: y - len))
            ctx.addLine(to: CGPoint(x: x, y: y + len))
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Draw text preview
        if isEditing && !previewText.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: previewFont,
                .foregroundColor: previewColor,
            ]
            let attrString = NSAttributedString(string: previewText, attributes: attrs)

            ctx.saveGState()
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx
            attrString.draw(at: previewLocation)
            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()
        }
    }

    // MARK: - Preview Updates

    func updatePreview(text: String, fontName: String, fontSize: CGFloat,
                       isBold: Bool, isItalic: Bool, color: NSColor) {
        previewText = text
        editingFontName = fontName
        editingFontSize = fontSize
        editingBold = isBold
        editingItalic = isItalic
        previewColor = color

        var font = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let fm = NSFontManager.shared
        if isBold {
            font = fm.convert(font, toHaveTrait: .boldFontMask)
        }
        if isItalic {
            font = fm.convert(font, toHaveTrait: .italicFontMask)
        }
        previewFont = font
    }

    // MARK: - Commit / Cancel

    func commitText(canvas: CanvasView) {
        guard isEditing, !previewText.isEmpty else {
            cancelText(canvas: canvas)
            return
        }

        let content = TextContent(
            text: previewText,
            fontName: editingFontName,
            fontSize: editingFontSize,
            isBold: editingBold,
            isItalic: editingItalic,
            color: previewColor,
            position: previewLocation
        )

        if let existingLayer = editingExistingLayer {
            // RE-EDIT: update existing text layer
            // Undo snapshot was already taken in mouseDown
            existingLayer.textContent = content
            canvas.canvasModel.registerUndoForActiveLayer(actionName: "Edit Text")
        } else {
            // CREATION: add a new text layer
            canvas.canvasModel.layerStack.addTextLayer(content: content)
            canvas.canvasModel.registerUndoForLayerAddition(
                at: canvas.canvasModel.layerStack.activeLayerIndex,
                actionName: "Add Text"
            )
        }

        isEditing = false
        editingExistingLayer = nil
        previewText = ""
        canvas.compositeDirty = true
        canvas.needsDisplay = true
    }

    func cancelText(canvas: CanvasView) {
        if editingExistingLayer != nil {
            // Restore original state from pending snapshot
            if let snapshot = canvas.canvasModel.pendingSnapshot,
               let layer = canvas.canvasModel.layerStack.layers[safe: snapshot.layerIndex] {
                layer.restoreFromImage(snapshot.image)
                layer.restoreTextContent(snapshot.textContent)
            }
            canvas.canvasModel.clearPendingSnapshot()
        }
        isEditing = false
        editingExistingLayer = nil
        previewText = ""
        canvas.compositeDirty = true
        canvas.needsDisplay = true
    }
}
