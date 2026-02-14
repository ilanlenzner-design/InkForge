import Foundation
import CoreGraphics

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

func lerp(_ a: CGFloat, _ b: CGFloat, t: CGFloat) -> CGFloat {
    return a + (b - a) * t
}

func lerp(_ a: Double, _ b: Double, t: Double) -> Double {
    return a + (b - a) * t
}

func lerp(_ a: CGPoint, _ b: CGPoint, t: CGFloat) -> CGPoint {
    return CGPoint(x: lerp(a.x, b.x, t: t), y: lerp(a.y, b.y, t: t))
}

func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    return hypot(b.x - a.x, b.y - a.y)
}

/// Returns a unit vector perpendicular to the direction from p1 to p2
func perpendicular(from p1: CGPoint, to p2: CGPoint) -> CGPoint {
    let dx = p2.x - p1.x
    let dy = p2.y - p1.y
    let len = hypot(dx, dy)
    guard len > 0.0001 else { return CGPoint(x: 0, y: -1) }
    return CGPoint(x: -dy / len, y: dx / len)
}

/// Angle in radians from p1 to p2
func angle(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
    return atan2(p2.y - p1.y, p2.x - p1.x)
}

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
