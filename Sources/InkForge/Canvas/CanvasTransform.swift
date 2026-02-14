import Foundation
import CoreGraphics

class CanvasTransform {
    var scale: CGFloat = 1.0 {
        didSet { scale = scale.clamped(to: 0.05...32.0) }
    }

    var rotation: CGFloat = 0 {  // degrees
        didSet { rotation = rotation.clamped(to: -180...180) }
    }

    var offset: CGPoint = .zero

    /// Center of the canvas in canvas coordinates. Set by CanvasView before use.
    var canvasCenter: CGPoint = .zero

    var affineTransform: CGAffineTransform {
        let rad = rotation * .pi / 180
        // Chain: translate by offset, scale, then rotate around canvas center
        return CGAffineTransform(translationX: offset.x, y: offset.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: canvasCenter.x, y: canvasCenter.y)
            .rotated(by: rad)
            .translatedBy(x: -canvasCenter.x, y: -canvasCenter.y)
    }

    func viewToCanvas(_ viewPoint: CGPoint) -> CGPoint {
        return viewPoint.applying(affineTransform.inverted())
    }

    func canvasToView(_ canvasPoint: CGPoint) -> CGPoint {
        return canvasPoint.applying(affineTransform)
    }

    func canvasToViewRect(_ canvasRect: CGRect) -> CGRect {
        return canvasRect.applying(affineTransform)
    }

    func zoom(by factor: CGFloat, centeredOn viewPoint: CGPoint) {
        let canvasPoint = viewToCanvas(viewPoint)
        scale *= factor
        // Recompute offset so canvasPoint maps back to viewPoint under new scale
        let viewAfter = canvasToView(canvasPoint)
        offset.x += viewPoint.x - viewAfter.x
        offset.y += viewPoint.y - viewAfter.y
    }

    func resetZoom(canvasSize: CGSize, viewSize: CGSize) {
        rotation = 0
        let scaleX = viewSize.width / canvasSize.width
        let scaleY = viewSize.height / canvasSize.height
        scale = min(scaleX, scaleY) * 0.9
        offset = CGPoint(
            x: (viewSize.width - canvasSize.width * scale) / 2,
            y: (viewSize.height - canvasSize.height * scale) / 2
        )
    }

    var zoomPercentage: Int {
        return Int(scale * 100)
    }
}
