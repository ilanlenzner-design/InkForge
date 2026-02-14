import AppKit

class PanTool: Tool {
    let name = "Pan"
    var cursor: NSCursor { .openHand }

    private var lastDragPoint: CGPoint = .zero

    func mouseDown(event: NSEvent, canvas: CanvasView) {
        lastDragPoint = event.locationInWindow
        NSCursor.closedHand.push()
    }

    func mouseDragged(event: NSEvent, canvas: CanvasView) {
        let current = event.locationInWindow
        let dx = current.x - lastDragPoint.x
        let dy = current.y - lastDragPoint.y
        canvas.canvasTransform.offset.x += dx
        canvas.canvasTransform.offset.y -= dy
        lastDragPoint = current
        canvas.needsDisplay = true
    }

    func mouseUp(event: NSEvent, canvas: CanvasView) {
        NSCursor.pop()
    }
}
