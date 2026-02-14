import Foundation
import CoreGraphics

struct DetectedShape {
    enum Kind {
        case line(from: CGPoint, to: CGPoint)
        case ellipse(center: CGPoint, radiusX: CGFloat, radiusY: CGFloat)
        case rectangle(CGRect)
    }
    let kind: Kind
}

class ShapeDetector {

    /// Analyze stroke points. Returns a detected shape if the stroke matches, nil otherwise.
    static func detect(from points: [CGPoint]) -> DetectedShape? {
        guard points.count >= 5 else { return nil }

        // Check for straight line first
        if let line = detectLine(points) { return line }

        // Must be roughly closed for shape detection
        let first = points.first!
        let last = points.last!
        let totalLen = pathLength(points)
        let closeDist = hypot(last.x - first.x, last.y - first.y)
        guard closeDist < totalLen * 0.25 else { return nil }

        // Check rectangle before ellipse (rectangles are a subset of closed shapes)
        if let rect = detectRectangle(points) { return rect }
        if let ellipse = detectEllipse(points) { return ellipse }

        return nil
    }

    // MARK: - Line Detection

    private static func detectLine(_ points: [CGPoint]) -> DetectedShape? {
        let first = points.first!
        let last = points.last!
        let lineLen = hypot(last.x - first.x, last.y - first.y)
        guard lineLen > 10 else { return nil }

        // Check that all points are close to the line from first to last
        let dx = last.x - first.x
        let dy = last.y - first.y

        var maxDist: CGFloat = 0
        for p in points {
            let t = max(0, min(1, ((p.x - first.x) * dx + (p.y - first.y) * dy) / (lineLen * lineLen)))
            let projX = first.x + t * dx
            let projY = first.y + t * dy
            let dist = hypot(p.x - projX, p.y - projY)
            maxDist = max(maxDist, dist)
        }

        // Allow deviation up to 5% of line length
        if maxDist < lineLen * 0.05 {
            return DetectedShape(kind: .line(from: first, to: last))
        }
        return nil
    }

    // MARK: - Ellipse / Circle Detection

    private static func detectEllipse(_ points: [CGPoint]) -> DetectedShape? {
        // Compute bounding box
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        let minX = xs.min()!
        let maxX = xs.max()!
        let minY = ys.min()!
        let maxY = ys.max()!

        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        let rx = (maxX - minX) / 2
        let ry = (maxY - minY) / 2

        guard rx > 5, ry > 5 else { return nil }

        // Check that all points lie roughly on the ellipse
        var maxError: CGFloat = 0
        let avgRadius = (rx + ry) / 2

        for p in points {
            let dx = (p.x - cx) / rx
            let dy = (p.y - cy) / ry
            let dist = sqrt(dx * dx + dy * dy)
            let error = abs(dist - 1.0) * avgRadius
            maxError = max(maxError, error)
        }

        // Allow deviation up to 10% of average radius
        if maxError < avgRadius * 0.1 {
            return DetectedShape(kind: .ellipse(center: CGPoint(x: cx, y: cy),
                                                radiusX: rx, radiusY: ry))
        }
        return nil
    }

    // MARK: - Rectangle Detection

    private static func detectRectangle(_ points: [CGPoint]) -> DetectedShape? {
        // Find corners by detecting sharp angle changes
        let corners = findCorners(points, minAngle: 50)

        // A rectangle should have exactly 4 corners
        guard corners.count == 4 else { return nil }

        _ = corners.sorted { $0.x + $0.y < $1.x + $1.y }

        // Check that corners form roughly a rectangle
        // Use the bounding box of the corners
        let xs = corners.map { $0.x }
        let ys = corners.map { $0.y }
        let rect = CGRect(x: xs.min()!, y: ys.min()!,
                          width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)

        guard rect.width > 10, rect.height > 10 else { return nil }

        // Check that all 4 corners are near the rect corners
        let rectCorners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ]

        let diag = hypot(rect.width, rect.height)
        let threshold = diag * 0.12

        for corner in corners {
            let minDist = rectCorners.map { hypot($0.x - corner.x, $0.y - corner.y) }.min()!
            if minDist > threshold { return nil }
        }

        // Check that points stay close to the rect edges
        var maxDist: CGFloat = 0
        for p in points {
            let distToEdge = min(
                abs(p.x - rect.minX), abs(p.x - rect.maxX),
                abs(p.y - rect.minY), abs(p.y - rect.maxY)
            )
            // Only count distance if point is well inside the rect
            let insetRect = rect.insetBy(dx: -threshold, dy: -threshold)
            if insetRect.contains(p) {
                maxDist = max(maxDist, min(distToEdge, threshold))
            }
        }

        if maxDist < threshold {
            return DetectedShape(kind: .rectangle(rect))
        }
        return nil
    }

    // MARK: - Helpers

    private static func pathLength(_ points: [CGPoint]) -> CGFloat {
        var total: CGFloat = 0
        for i in 1..<points.count {
            total += hypot(points[i].x - points[i-1].x, points[i].y - points[i-1].y)
        }
        return total
    }

    private static func findCorners(_ points: [CGPoint], minAngle: CGFloat) -> [CGPoint] {
        guard points.count > 10 else { return [] }

        var corners: [CGPoint] = []
        let step = max(1, points.count / 40)  // Sample every ~2.5% of points

        for i in stride(from: step, to: points.count - step, by: 1) {
            let prev = points[max(0, i - step)]
            let curr = points[i]
            let next = points[min(points.count - 1, i + step)]

            let v1x = curr.x - prev.x
            let v1y = curr.y - prev.y
            let v2x = next.x - curr.x
            let v2y = next.y - curr.y

            let len1 = hypot(v1x, v1y)
            let len2 = hypot(v2x, v2y)
            guard len1 > 1, len2 > 1 else { continue }

            let dot = v1x * v2x + v1y * v2y
            let cosAngle = dot / (len1 * len2)
            let angle = acos(min(1, max(-1, cosAngle))) * 180 / .pi

            if angle > minAngle {
                // Check this isn't too close to an existing corner
                let tooClose = corners.contains { hypot($0.x - curr.x, $0.y - curr.y) < 20 }
                if !tooClose {
                    corners.append(curr)
                }
            }
        }

        return corners
    }
}
