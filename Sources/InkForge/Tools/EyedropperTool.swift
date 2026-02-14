import AppKit

class EyedropperTool: Tool {
    let name = "Eyedropper"
    var cursor: NSCursor { .crosshair }

    func mouseDown(event: NSEvent, canvas: CanvasView) {
        pickColor(event: event, canvas: canvas)
    }

    func mouseDragged(event: NSEvent, canvas: CanvasView) {
        pickColor(event: event, canvas: canvas)
    }

    func mouseUp(event: NSEvent, canvas: CanvasView) {}

    private func pickColor(event: NSEvent, canvas: CanvasView) {
        let viewPoint = canvas.convert(event.locationInWindow, from: nil)
        let canvasPoint = canvas.canvasPoint(from: viewPoint)

        guard let composite = canvas.canvasModel.layerStack.compositeImage() else { return }

        let x = Int(canvasPoint.x)
        let y = Int(canvasPoint.y)
        let width = composite.width
        let height = composite.height

        guard x >= 0, x < width, y >= 0, y < height else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let ctx = CGContext(data: &pixel,
                                   width: 1, height: 1,
                                   bitsPerComponent: 8, bytesPerRow: 4,
                                   space: colorSpace,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }

        ctx.draw(composite, in: CGRect(x: -x, y: -(height - y - 1), width: width, height: height))

        let r = CGFloat(pixel[0]) / 255.0
        let g = CGFloat(pixel[1]) / 255.0
        let b = CGFloat(pixel[2]) / 255.0
        let a = CGFloat(pixel[3]) / 255.0

        let color = NSColor(red: r, green: g, blue: b, alpha: a > 0 ? 1.0 : 1.0)
        canvas.toolManager?.currentColor = color
    }
}
