import AppKit

protocol Tool: AnyObject {
    var name: String { get }
    var cursor: NSCursor { get }
    func mouseDown(event: NSEvent, canvas: CanvasView)
    func mouseDragged(event: NSEvent, canvas: CanvasView)
    func mouseUp(event: NSEvent, canvas: CanvasView)
    func drawOverlay(in ctx: CGContext, canvas: CanvasView)
    func handleKeyDown(event: NSEvent, canvas: CanvasView) -> Bool
}

extension Tool {
    func drawOverlay(in ctx: CGContext, canvas: CanvasView) {}
    func handleKeyDown(event: NSEvent, canvas: CanvasView) -> Bool { return false }
}
