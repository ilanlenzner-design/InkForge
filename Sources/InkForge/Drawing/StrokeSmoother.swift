import Foundation
import CoreGraphics

/// Exponential moving average filter for real-time stroke smoothing.
/// StreamLine value 0 = raw input, 1 = maximum smoothing.
class StrokeSmoother {
    private var smoothedX: CGFloat = 0
    private var smoothedY: CGFloat = 0
    private var isStarted = false
    private let amount: CGFloat  // 0...1

    init(amount: CGFloat) {
        self.amount = amount.clamped(to: 0...1)
    }

    func reset() {
        isStarted = false
    }

    /// Smooth a raw canvas point. Returns the smoothed position.
    func smooth(_ point: CGPoint) -> CGPoint {
        if !isStarted {
            smoothedX = point.x
            smoothedY = point.y
            isStarted = true
            return point
        }

        // weight = 1 - amount: at amount=0, weight=1 (no smoothing), at amount=1, weight ~0.05 (heavy smoothing)
        let weight = 1.0 - amount * 0.95
        smoothedX += (point.x - smoothedX) * weight
        smoothedY += (point.y - smoothedY) * weight

        return CGPoint(x: smoothedX, y: smoothedY)
    }
}
