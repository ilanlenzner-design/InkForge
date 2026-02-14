import Foundation
import CoreGraphics

struct StrokeInterpolator {

    static func catmullRom(points: [StrokePoint], segmentsPerCurve: Int = 4) -> [StrokePoint] {
        guard points.count >= 2 else { return points }

        var result: [StrokePoint] = []

        for i in 0..<points.count - 1 {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(i + 2, points.count - 1)]

            for s in 0..<segmentsPerCurve {
                let t = CGFloat(s) / CGFloat(segmentsPerCurve)

                let x = catmullRomValue(p0.location.x, p1.location.x,
                                        p2.location.x, p3.location.x, t: t)
                let y = catmullRomValue(p0.location.y, p1.location.y,
                                        p2.location.y, p3.location.y, t: t)
                let pressure = lerp(p1.pressure, p2.pressure, t: t)
                let tiltX = lerp(p1.tiltX, p2.tiltX, t: t)
                let tiltY = lerp(p1.tiltY, p2.tiltY, t: t)
                let rotation = lerp(p1.rotation, p2.rotation, t: t)
                let timestamp = lerp(p1.timestamp, p2.timestamp, t: Double(t))

                result.append(StrokePoint(
                    location: CGPoint(x: x, y: y),
                    pressure: pressure, tiltX: tiltX, tiltY: tiltY,
                    rotation: rotation, timestamp: timestamp
                ))
            }
        }
        result.append(points.last!)
        return result
    }

    private static func catmullRomValue(_ v0: CGFloat, _ v1: CGFloat,
                                         _ v2: CGFloat, _ v3: CGFloat,
                                         t: CGFloat) -> CGFloat {
        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * ((2 * v1) +
                       (-v0 + v2) * t +
                       (2 * v0 - 5 * v1 + 4 * v2 - v3) * t2 +
                       (-v0 + 3 * v1 - 3 * v2 + v3) * t3)
    }
}
