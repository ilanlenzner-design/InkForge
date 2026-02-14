import AppKit

class ZoomTool: Tool {
    let name = "Zoom"
    var cursor: NSCursor {
        return NSCursor(image: zoomCursorImage(), hotSpot: NSPoint(x: 6, y: 6))
    }

    private var anchorViewPoint: CGPoint = .zero
    private var lastDragPoint: CGPoint = .zero

    func mouseDown(event: NSEvent, canvas: CanvasView) {
        let viewPoint = canvas.convert(event.locationInWindow, from: nil)
        anchorViewPoint = viewPoint
        lastDragPoint = viewPoint
    }

    func mouseDragged(event: NSEvent, canvas: CanvasView) {
        let viewPoint = canvas.convert(event.locationInWindow, from: nil)
        let dx = viewPoint.x - lastDragPoint.x
        let dy = -(viewPoint.y - lastDragPoint.y) // flipped: drag up = positive

        // Horizontal + vertical movement both contribute to zoom
        let delta = (dx + dy) * 0.005
        let factor = 1.0 + delta
        canvas.canvasTransform.zoom(by: factor, centeredOn: anchorViewPoint)
        canvas.needsDisplay = true
        NotificationCenter.default.post(name: .canvasTransformChanged, object: canvas)

        lastDragPoint = viewPoint
    }

    func mouseUp(event: NSEvent, canvas: CanvasView) {}

    private func zoomCursorImage() -> NSImage {
        let size: CGFloat = 16
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.darkGray.setStroke()
        let circle = NSBezierPath(ovalIn: NSRect(x: 1, y: 5, width: 10, height: 10))
        circle.lineWidth = 1.5
        circle.stroke()
        let handle = NSBezierPath()
        handle.move(to: NSPoint(x: 10, y: 6))
        handle.line(to: NSPoint(x: 14, y: 2))
        handle.lineWidth = 2
        handle.stroke()
        // Plus sign
        let plus = NSBezierPath()
        plus.move(to: NSPoint(x: 6, y: 8))
        plus.line(to: NSPoint(x: 6, y: 12))
        plus.move(to: NSPoint(x: 4, y: 10))
        plus.line(to: NSPoint(x: 8, y: 10))
        plus.lineWidth = 1
        plus.stroke()
        image.unlockFocus()
        return image
    }
}
