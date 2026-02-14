import Foundation
import CoreGraphics

struct StrokePoint {
    let location: CGPoint
    let pressure: CGFloat
    let tiltX: CGFloat
    let tiltY: CGFloat
    let rotation: CGFloat
    let timestamp: TimeInterval

    var tiltMagnitude: CGFloat {
        return hypot(tiltX, tiltY).clamped(to: 0...1)
    }

    var tiltAzimuth: CGFloat {
        return atan2(tiltY, tiltX)
    }
}
