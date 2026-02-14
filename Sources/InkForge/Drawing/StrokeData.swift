import Foundation
import AppKit

func symmetryMirrorPoints(_ point: CGPoint, mode: SymmetryMode,
                          axisX: CGFloat, axisY: CGFloat) -> [CGPoint] {
    switch mode {
    case .off: return []
    case .vertical:
        return [CGPoint(x: 2 * axisX - point.x, y: point.y)]
    case .horizontal:
        return [CGPoint(x: point.x, y: 2 * axisY - point.y)]
    case .quadrant:
        return [
            CGPoint(x: 2 * axisX - point.x, y: point.y),
            CGPoint(x: point.x, y: 2 * axisY - point.y),
            CGPoint(x: 2 * axisX - point.x, y: 2 * axisY - point.y),
        ]
    }
}

class StrokeData {
    var points: [StrokePoint] = []
    var brushPreset: BrushPreset
    var color: NSColor
    var layerIndex: Int

    init(brushPreset: BrushPreset, color: NSColor, layerIndex: Int) {
        self.brushPreset = brushPreset
        self.color = color
        self.layerIndex = layerIndex
    }

    func addPoint(_ point: StrokePoint) {
        points.append(point)
    }

    // MARK: - Symmetry Mirroring

    func mirrored(verticalAxis axisX: CGFloat? = nil,
                  horizontalAxis axisY: CGFloat? = nil) -> StrokeData {
        let copy = StrokeData(brushPreset: brushPreset, color: color, layerIndex: layerIndex)
        for p in points {
            var loc = p.location
            var tx = p.tiltX
            var ty = p.tiltY
            if let ax = axisX {
                loc.x = 2 * ax - loc.x
                tx = -tx
            }
            if let ay = axisY {
                loc.y = 2 * ay - loc.y
                ty = -ty
            }
            copy.addPoint(StrokePoint(
                location: loc, pressure: p.pressure,
                tiltX: tx, tiltY: ty,
                rotation: p.rotation, timestamp: p.timestamp
            ))
        }
        return copy
    }

    func symmetryMirrors(mode: SymmetryMode, axisX: CGFloat, axisY: CGFloat) -> [StrokeData] {
        switch mode {
        case .off:        return []
        case .vertical:   return [mirrored(verticalAxis: axisX)]
        case .horizontal: return [mirrored(horizontalAxis: axisY)]
        case .quadrant:
            return [
                mirrored(verticalAxis: axisX),
                mirrored(horizontalAxis: axisY),
                mirrored(verticalAxis: axisX, horizontalAxis: axisY),
            ]
        }
    }

    // MARK: - Geometry

    var boundingRect: CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.location.x, maxX = first.location.x
        var minY = first.location.y, maxY = first.location.y
        for p in points {
            minX = min(minX, p.location.x)
            maxX = max(maxX, p.location.x)
            minY = min(minY, p.location.y)
            maxY = max(maxY, p.location.y)
        }
        let pad = brushPreset.maxRadius + 2
        return CGRect(x: minX - pad, y: minY - pad,
                      width: maxX - minX + pad * 2,
                      height: maxY - minY + pad * 2)
    }
}
