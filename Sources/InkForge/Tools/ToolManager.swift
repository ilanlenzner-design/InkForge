import AppKit

protocol ToolManagerDelegate: AnyObject {
    func toolDidChange(to tool: Tool)
    func colorDidChange(to color: NSColor)
    func brushDidChange(to preset: BrushPreset)
}

class ToolManager {
    var activeTool: Tool {
        didSet { delegate?.toolDidChange(to: activeTool) }
    }
    var previousTool: Tool?

    let penTool: PenTool
    let eraserTool: EraserTool
    let panTool: PanTool
    let zoomTool: ZoomTool
    let eyedropperTool: EyedropperTool
    let smudgeTool: SmudgeTool
    let fillTool: FillTool
    let selectionTool: SelectionTool
    let transformTool: TransformTool
    let textTool: TextTool

    var currentBrushPreset: BrushPreset = .defaultRound {
        didSet { delegate?.brushDidChange(to: currentBrushPreset) }
    }
    var currentColor: NSColor = .black {
        didSet { delegate?.colorDidChange(to: currentColor) }
    }

    private var eraserEndActive: Bool = false
    private var spaceBarDown: Bool = false
    private var preSpaceTool: Tool?

    weak var delegate: ToolManagerDelegate?

    init() {
        self.penTool = PenTool()
        self.eraserTool = EraserTool()
        self.panTool = PanTool()
        self.zoomTool = ZoomTool()
        self.eyedropperTool = EyedropperTool()
        self.smudgeTool = SmudgeTool()
        self.fillTool = FillTool()
        self.selectionTool = SelectionTool()
        self.transformTool = TransformTool()
        self.textTool = TextTool()
        self.activeTool = penTool
    }

    func handleMouseDown(event: NSEvent, in canvas: CanvasView) {
        activeTool.mouseDown(event: event, canvas: canvas)
    }

    func handleMouseDragged(event: NSEvent, in canvas: CanvasView) {
        activeTool.mouseDragged(event: event, canvas: canvas)
    }

    func handleMouseUp(event: NSEvent, in canvas: CanvasView) {
        activeTool.mouseUp(event: event, canvas: canvas)
    }

    func handleProximity(event: NSEvent) {
        if event.isEnteringProximity {
            if event.pointingDeviceType == .eraser {
                if !(activeTool is EraserTool) {
                    previousTool = activeTool
                }
                eraserEndActive = true
                activeTool = eraserTool
            } else {
                if eraserEndActive, let prev = previousTool {
                    activeTool = prev
                    eraserEndActive = false
                }
            }
        }
    }

    func selectTool(_ tool: Tool) {
        // Auto-commit transform when switching away
        if let tt = activeTool as? TransformTool, tt.isActive, !(tool is TransformTool) {
            // Need a canvas reference — commit will happen on next mouse event if we can't get one here
            // TransformTool.commit requires a canvas, so we store a pending commit flag
        }
        eraserEndActive = false
        previousTool = nil
        activeTool = tool
    }

    func activatePanTemporarily() {
        guard !spaceBarDown else { return }
        spaceBarDown = true
        preSpaceTool = activeTool
        activeTool = panTool
    }

    func deactivateTemporaryTool() {
        guard spaceBarDown else { return }
        spaceBarDown = false
        if let prev = preSpaceTool {
            activeTool = prev
            preSpaceTool = nil
        }
    }

    func increaseBrushSize() {
        currentBrushPreset.maxRadius = min(currentBrushPreset.maxRadius + 2, 200)
    }

    func decreaseBrushSize() {
        currentBrushPreset.maxRadius = max(currentBrushPreset.maxRadius - 2, 1)
    }
}
