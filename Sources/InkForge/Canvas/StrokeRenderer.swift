import Foundation
import CoreGraphics
import AppKit

class StrokeRenderer {

    /// Render a stroke. When `preview` is true, eraser strokes are shown as a
    /// translucent highlight instead of using `.clear` blend mode (which only
    /// works correctly when rendering into a layer's bitmap context).
    func renderStroke(_ stroke: StrokeData, into ctx: CGContext, preview: Bool = false) {
        let points = stroke.points
        guard points.count >= 2 else {
            if let p = points.first {
                renderDot(at: p, brush: stroke.brushPreset, color: stroke.color,
                          into: ctx, preview: preview)
            }
            return
        }

        switch stroke.brushPreset.type {
        case .round:
            renderRoundStroke(points: points, brush: stroke.brushPreset,
                              color: stroke.color, into: ctx)
        case .pencil:
            renderPencilStroke(points: points, brush: stroke.brushPreset,
                               color: stroke.color, into: ctx)
        case .calligraphy:
            renderCalligraphyStroke(points: points, brush: stroke.brushPreset,
                                    color: stroke.color, into: ctx)
        case .airbrush:
            renderAirbrushStroke(points: points, brush: stroke.brushPreset,
                                 color: stroke.color, into: ctx)
        case .spray:
            renderSprayStroke(points: points, brush: stroke.brushPreset,
                              color: stroke.color, into: ctx)
        case .marker:
            renderMarkerStroke(points: points, brush: stroke.brushPreset,
                               color: stroke.color, into: ctx)
        case .softRound:
            renderSoftRoundStroke(points: points, brush: stroke.brushPreset,
                                  color: stroke.color, into: ctx)
        case .eraser:
            if preview {
                // Preview: translucent white highlight showing where the eraser will affect
                ctx.saveGState()
                ctx.setAlpha(0.45)
                renderRoundStroke(points: points, brush: stroke.brushPreset,
                                  color: .white, into: ctx)
                ctx.restoreGState()
            } else {
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                renderRoundStroke(points: points, brush: stroke.brushPreset,
                                  color: .white, into: ctx)
                ctx.restoreGState()
            }
        }
    }

    // MARK: - Dot (single click)

    private func renderDot(at point: StrokePoint, brush: BrushPreset,
                           color: NSColor, into ctx: CGContext,
                           preview: Bool = false) {
        let radius = brush.radiusForPressure(point.pressure)
        let rect = CGRect(x: point.location.x - radius,
                          y: point.location.y - radius,
                          width: radius * 2, height: radius * 2)

        switch brush.type {
        case .eraser:
            if preview {
                ctx.saveGState()
                ctx.setFillColor(NSColor.white.withAlphaComponent(0.45).cgColor)
                ctx.fillEllipse(in: rect)
                ctx.restoreGState()
            } else {
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: rect)
                ctx.restoreGState()
            }
        case .spray:
            stampSprayDab(at: point.location, radius: radius,
                          pressure: point.pressure, brush: brush,
                          color: color, into: ctx)
        case .pencil:
            stampPencilDab(at: point.location, pressure: point.pressure,
                           tiltX: point.tiltX, tiltY: point.tiltY,
                           brush: brush, color: color, into: ctx)
        case .marker:
            stampMarkerDab(at: point.location, pressure: point.pressure,
                           brush: brush, color: color, into: ctx)
        case .softRound:
            stampSoftRoundDab(at: point.location, radius: radius,
                              pressure: point.pressure, brush: brush,
                              color: color, into: ctx)
        default:
            if brush.tipType != .circle {
                stampTextureDab(at: point.location, radius: radius,
                                pressure: point.pressure, brush: brush,
                                color: color, direction: 0,
                                tiltAzimuth: atan2(point.tiltY, point.tiltX), into: ctx)
            } else {
                ctx.setFillColor(color.withAlphaComponent(brush.opacity).cgColor)
                ctx.fillEllipse(in: rect)
            }
        }
    }

    // MARK: - Texture Dab Stamping

    private func stampTextureDab(at center: CGPoint, radius: CGFloat,
                                 pressure: CGFloat, brush: BrushPreset,
                                 color: NSColor, direction: CGFloat,
                                 tiltAzimuth: CGFloat, into ctx: CGContext) {
        guard let tipImage = BrushTipCache.shared.tipImage(for: brush.tipType) else {
            ctx.setFillColor(color.withAlphaComponent(brush.opacity * brush.flow * pressure).cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                        width: radius * 2, height: radius * 2))
            return
        }

        var dabRadius = radius
        if brush.sizeJitter > 0 {
            dabRadius *= 1.0 - brush.sizeJitter * CGFloat.random(in: 0...1)
        }

        var rotAngle: CGFloat = 0
        switch brush.tipRotation {
        case .fixed:           rotAngle = 0
        case .followDirection: rotAngle = direction
        case .random:          rotAngle = CGFloat.random(in: 0...(2 * .pi))
        case .tiltAzimuth:     rotAngle = tiltAzimuth
        }
        if brush.rotationJitter > 0 {
            rotAngle += brush.rotationJitter * .pi * CGFloat.random(in: -1...1)
        }

        let dabAlpha = brush.flow * pressure * brush.opacity
        let dabSize = dabRadius * 2
        let dabRect = CGRect(x: -dabRadius, y: -dabRadius, width: dabSize, height: dabSize)

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        if rotAngle != 0 { ctx.rotate(by: rotAngle) }

        let flipX: CGFloat = (brush.tipFlipX && Bool.random()) ? -1 : 1
        let flipY: CGFloat = (brush.tipFlipY && Bool.random()) ? -1 : 1
        if flipX == -1 || flipY == -1 { ctx.scaleBy(x: flipX, y: flipY) }

        ctx.clip(to: dabRect, mask: tipImage)
        ctx.setFillColor(color.withAlphaComponent(dabAlpha).cgColor)
        ctx.fill(dabRect)
        ctx.restoreGState()
    }

    // MARK: - Round Brush (Dab-based)

    private func renderRoundStroke(points: [StrokePoint], brush: BrushPreset,
                                    color: NSColor, into ctx: CGContext) {
        let useTexture = brush.tipType != .circle
        let interpolated = StrokeInterpolator.catmullRom(points: points, segmentsPerCurve: 4)
        guard interpolated.count >= 2 else { return }

        if !useTexture {
            ctx.setFillColor(color.withAlphaComponent(brush.opacity).cgColor)
        }

        // Stamp first dab
        let firstRadius = brush.radiusForPressure(interpolated[0].pressure)
        if useTexture {
            let dir = angle(from: interpolated[0].location, to: interpolated[1].location)
            stampTextureDab(at: interpolated[0].location, radius: firstRadius,
                            pressure: interpolated[0].pressure, brush: brush,
                            color: color, direction: dir,
                            tiltAzimuth: interpolated[0].tiltAzimuth, into: ctx)
        } else {
            ctx.fillEllipse(in: CGRect(x: interpolated[0].location.x - firstRadius,
                                        y: interpolated[0].location.y - firstRadius,
                                        width: firstRadius * 2, height: firstRadius * 2))
        }

        var distAccum: CGFloat = 0

        for i in 1..<interpolated.count {
            let prev = interpolated[i - 1]
            let curr = interpolated[i]
            let dist = distance(prev.location, curr.location)
            distAccum += dist
            let dir = angle(from: prev.location, to: curr.location)

            let radius = brush.radiusForPressure(curr.pressure)
            let spacingDist = max(radius * 2 * brush.spacing, 0.5)

            while distAccum >= spacingDist {
                distAccum -= spacingDist
                let t = dist > 0 ? (1 - distAccum / dist).clamped(to: 0...1) : 1
                let dabPoint = lerp(prev.location, curr.location, t: t)
                let dabPressure = lerp(prev.pressure, curr.pressure, t: t)
                let dabRadius = brush.radiusForPressure(dabPressure)

                if useTexture {
                    let dabTiltX = lerp(prev.tiltX, curr.tiltX, t: t)
                    let dabTiltY = lerp(prev.tiltY, curr.tiltY, t: t)
                    stampTextureDab(at: dabPoint, radius: dabRadius,
                                    pressure: dabPressure, brush: brush,
                                    color: color, direction: dir,
                                    tiltAzimuth: atan2(dabTiltY, dabTiltX), into: ctx)
                } else {
                    ctx.fillEllipse(in: CGRect(x: dabPoint.x - dabRadius,
                                                y: dabPoint.y - dabRadius,
                                                width: dabRadius * 2, height: dabRadius * 2))
                }
            }
        }

        // Stamp last dab
        let lastPt = interpolated.last!
        let lastRadius = brush.radiusForPressure(lastPt.pressure)
        if useTexture {
            let secondLast = interpolated[interpolated.count - 2]
            let dir = angle(from: secondLast.location, to: lastPt.location)
            stampTextureDab(at: lastPt.location, radius: lastRadius,
                            pressure: lastPt.pressure, brush: brush,
                            color: color, direction: dir,
                            tiltAzimuth: lastPt.tiltAzimuth, into: ctx)
        } else {
            ctx.fillEllipse(in: CGRect(x: lastPt.location.x - lastRadius,
                                        y: lastPt.location.y - lastRadius,
                                        width: lastRadius * 2, height: lastRadius * 2))
        }
    }

    // MARK: - Calligraphy Brush (Tilt-responsive elliptical dabs)

    private func renderCalligraphyStroke(points: [StrokePoint], brush: BrushPreset,
                                          color: NSColor, into ctx: CGContext) {
        let interpolated = StrokeInterpolator.catmullRom(points: points, segmentsPerCurve: 6)
        guard interpolated.count >= 2 else { return }

        var distAccum: CGFloat = 0

        for i in 1..<interpolated.count {
            let prev = interpolated[i - 1]
            let curr = interpolated[i]
            let dist = distance(prev.location, curr.location)
            distAccum += dist

            let radius = brush.radiusForPressure(curr.pressure)
            let spacingDist = max(radius * 2 * brush.spacing, 0.5)

            while distAccum >= spacingDist {
                distAccum -= spacingDist
                let t = dist > 0 ? (1 - distAccum / dist).clamped(to: 0...1) : 1
                let dabPoint = lerp(prev.location, curr.location, t: t)
                let dabPressure = lerp(prev.pressure, curr.pressure, t: t)
                let dabTiltX = lerp(prev.tiltX, curr.tiltX, t: t)
                let dabTiltY = lerp(prev.tiltY, curr.tiltY, t: t)

                stampCalligraphyDab(at: dabPoint, pressure: dabPressure,
                                    tiltX: dabTiltX, tiltY: dabTiltY,
                                    brush: brush, color: color, into: ctx)
            }
        }
    }

    private func stampCalligraphyDab(at center: CGPoint, pressure: CGFloat,
                                      tiltX: CGFloat, tiltY: CGFloat,
                                      brush: BrushPreset, color: NSColor,
                                      into ctx: CGContext) {
        let baseRadius = brush.radiusForPressure(pressure)
        let tiltMag = hypot(tiltX, tiltY).clamped(to: 0...1)
        let tiltAngle = atan2(tiltY, tiltX)

        let influence = brush.tiltInfluence
        let aspectRatio: CGFloat = 1.0 + tiltMag * influence * 2.0

        let w = baseRadius * sqrt(aspectRatio)
        let h = baseRadius / sqrt(aspectRatio)

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: tiltAngle)

        let dabRect = CGRect(x: -w, y: -h, width: w * 2, height: h * 2)
        ctx.setFillColor(color.withAlphaComponent(brush.flow * pressure).cgColor)
        ctx.fillEllipse(in: dabRect)

        ctx.restoreGState()
    }

    // MARK: - Airbrush (Radial gradient dabs)

    private func renderAirbrushStroke(points: [StrokePoint], brush: BrushPreset,
                                       color: NSColor, into ctx: CGContext) {
        let interpolated = StrokeInterpolator.catmullRom(points: points, segmentsPerCurve: 4)
        guard interpolated.count >= 2 else { return }

        var distAccum: CGFloat = 0

        for i in 1..<interpolated.count {
            let prev = interpolated[i - 1]
            let curr = interpolated[i]
            let dist = distance(prev.location, curr.location)
            distAccum += dist

            let radius = brush.radiusForPressure(curr.pressure)
            let spacingDist = max(radius * 2 * brush.spacing, 1)

            while distAccum >= spacingDist {
                distAccum -= spacingDist
                let t = dist > 0 ? (1 - distAccum / dist).clamped(to: 0...1) : 1
                let dabPoint = lerp(prev.location, curr.location, t: t)
                let dabPressure = lerp(prev.pressure, curr.pressure, t: t)
                let dabRadius = brush.radiusForPressure(dabPressure)

                stampAirbrushDab(at: dabPoint, radius: dabRadius,
                                 pressure: dabPressure, brush: brush,
                                 color: color, into: ctx)
            }
        }
    }

    private func stampAirbrushDab(at center: CGPoint, radius: CGFloat,
                                   pressure: CGFloat, brush: BrushPreset,
                                   color: NSColor, into ctx: CGContext) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let rgbColor = color.usingColorSpace(.sRGB) ?? color
        rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        let dabOpacity = brush.flow * pressure * brush.opacity
        let colors = [
            CGColor(srgbRed: r, green: g, blue: b, alpha: dabOpacity),
            CGColor(srgbRed: r, green: g, blue: b, alpha: 0)
        ] as CFArray

        guard let gradient = CGGradient(colorsSpace: colorSpace,
                                         colors: colors,
                                         locations: [0, 1]) else { return }

        ctx.saveGState()
        ctx.clip(to: CGRect(x: center.x - radius, y: center.y - radius,
                             width: radius * 2, height: radius * 2))
        ctx.drawRadialGradient(gradient,
                                startCenter: center, startRadius: 0,
                                endCenter: center, endRadius: radius,
                                options: [])
        ctx.restoreGState()
    }

    // MARK: - Soft Round Brush (Dab-based, hardness-controlled gradient)

    private func renderSoftRoundStroke(points: [StrokePoint], brush: BrushPreset,
                                        color: NSColor, into ctx: CGContext) {
        let interpolated = StrokeInterpolator.catmullRom(points: points, segmentsPerCurve: 4)
        guard interpolated.count >= 2 else { return }

        var distAccum: CGFloat = 0

        for i in 1..<interpolated.count {
            let prev = interpolated[i - 1]
            let curr = interpolated[i]
            let dist = distance(prev.location, curr.location)
            distAccum += dist

            let radius = brush.radiusForPressure(curr.pressure)
            let spacingDist = max(radius * 2 * brush.spacing, 1)

            while distAccum >= spacingDist {
                distAccum -= spacingDist
                let t = dist > 0 ? (1 - distAccum / dist).clamped(to: 0...1) : 1
                let dabPoint = lerp(prev.location, curr.location, t: t)
                let dabPressure = lerp(prev.pressure, curr.pressure, t: t)
                let dabRadius = brush.radiusForPressure(dabPressure)

                stampSoftRoundDab(at: dabPoint, radius: dabRadius,
                                  pressure: dabPressure, brush: brush,
                                  color: color, into: ctx)
            }
        }
    }

    private func stampSoftRoundDab(at center: CGPoint, radius: CGFloat,
                                    pressure: CGFloat, brush: BrushPreset,
                                    color: NSColor, into ctx: CGContext) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let rgbColor = color.usingColorSpace(.sRGB) ?? color
        rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        let dabAlpha = brush.flow * pressure * brush.opacity
        let hardnessStop = brush.hardness.clamped(to: 0...0.99)

        let colors: [CGColor]
        let locations: [CGFloat]

        if hardnessStop > 0.01 {
            colors = [
                CGColor(srgbRed: r, green: g, blue: b, alpha: dabAlpha),
                CGColor(srgbRed: r, green: g, blue: b, alpha: dabAlpha),
                CGColor(srgbRed: r, green: g, blue: b, alpha: 0)
            ]
            locations = [0, hardnessStop, 1]
        } else {
            colors = [
                CGColor(srgbRed: r, green: g, blue: b, alpha: dabAlpha),
                CGColor(srgbRed: r, green: g, blue: b, alpha: 0)
            ]
            locations = [0, 1]
        }

        guard let gradient = CGGradient(colorsSpace: colorSpace,
                                         colors: colors as CFArray,
                                         locations: locations) else { return }

        ctx.saveGState()
        ctx.clip(to: CGRect(x: center.x - radius, y: center.y - radius,
                             width: radius * 2, height: radius * 2))
        ctx.drawRadialGradient(gradient,
                                startCenter: center, startRadius: 0,
                                endCenter: center, endRadius: radius,
                                options: [])
        ctx.restoreGState()
    }

    // MARK: - Marker Brush (Fixed-angle chisel, opacity buildup)

    private func renderMarkerStroke(points: [StrokePoint], brush: BrushPreset,
                                     color: NSColor, into ctx: CGContext) {
        let interpolated = StrokeInterpolator.catmullRom(points: points, segmentsPerCurve: 6)
        guard interpolated.count >= 2 else { return }

        var distAccum: CGFloat = 0

        for i in 1..<interpolated.count {
            let prev = interpolated[i - 1]
            let curr = interpolated[i]
            let dist = distance(prev.location, curr.location)
            distAccum += dist

            let radius = brush.radiusForPressure(curr.pressure)
            let spacingDist = max(radius * 2 * brush.spacing, 0.5)

            while distAccum >= spacingDist {
                distAccum -= spacingDist
                let t = dist > 0 ? (1 - distAccum / dist).clamped(to: 0...1) : 1
                let dabPoint = lerp(prev.location, curr.location, t: t)
                let dabPressure = lerp(prev.pressure, curr.pressure, t: t)

                stampMarkerDab(at: dabPoint, pressure: dabPressure,
                               brush: brush, color: color, into: ctx)
            }
        }
    }

    private func stampMarkerDab(at center: CGPoint, pressure: CGFloat,
                                 brush: BrushPreset, color: NSColor,
                                 into ctx: CGContext) {
        let baseRadius = brush.radiusForPressure(pressure)
        let aspectRatio: CGFloat = 3.0
        let w = baseRadius * sqrt(aspectRatio)
        let h = baseRadius / sqrt(aspectRatio)

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: brush.nibAngle)

        let dabRect = CGRect(x: -w, y: -h, width: w * 2, height: h * 2)
        ctx.setFillColor(color.withAlphaComponent(brush.flow * brush.opacity).cgColor)
        ctx.fillEllipse(in: dabRect)

        ctx.restoreGState()
    }

    // MARK: - Pencil Brush (Procedural grain/noise)

    private func renderPencilStroke(points: [StrokePoint], brush: BrushPreset,
                                     color: NSColor, into ctx: CGContext) {
        let interpolated = StrokeInterpolator.catmullRom(points: points, segmentsPerCurve: 6)
        guard interpolated.count >= 2 else { return }

        var distAccum: CGFloat = 0

        for i in 1..<interpolated.count {
            let prev = interpolated[i - 1]
            let curr = interpolated[i]
            let dist = distance(prev.location, curr.location)
            distAccum += dist

            let radius = brush.radiusForPressure(curr.pressure)
            let spacingDist = max(radius * 2 * brush.spacing, 0.5)

            while distAccum >= spacingDist {
                distAccum -= spacingDist
                let t = dist > 0 ? (1 - distAccum / dist).clamped(to: 0...1) : 1
                let dabPoint = lerp(prev.location, curr.location, t: t)
                let dabPressure = lerp(prev.pressure, curr.pressure, t: t)
                let dabTiltX = lerp(prev.tiltX, curr.tiltX, t: t)
                let dabTiltY = lerp(prev.tiltY, curr.tiltY, t: t)

                stampPencilDab(at: dabPoint, pressure: dabPressure,
                               tiltX: dabTiltX, tiltY: dabTiltY,
                               brush: brush, color: color, into: ctx)
            }
        }
    }

    private func stampPencilDab(at center: CGPoint, pressure: CGFloat,
                                 tiltX: CGFloat, tiltY: CGFloat,
                                 brush: BrushPreset, color: NSColor,
                                 into ctx: CGContext) {
        let baseRadius = brush.radiusForPressure(pressure)
        let grain = brush.grainIntensity

        let tiltMag = hypot(tiltX, tiltY).clamped(to: 0...1)
        let tiltAngle = atan2(tiltY, tiltX)
        let influence = brush.tiltInfluence
        let widthScale = 1.0 + tiltMag * influence * 1.5

        let grainCount = Int(8 + pressure * 12 * widthScale)

        for _ in 0..<grainCount {
            let jitterAngle = CGFloat.random(in: 0...(2 * .pi))
            let jitterDist = baseRadius * widthScale * CGFloat.random(in: 0...1)
            let px = center.x + cos(jitterAngle + tiltAngle * influence) * jitterDist
            let py = center.y + sin(jitterAngle + tiltAngle * influence) * jitterDist

            let grainOpacity = brush.flow * pressure * CGFloat.random(in: (1 - grain)...1)
            let particleSize = max(baseRadius * 0.15 * CGFloat.random(in: 0.5...1.2), 0.3)

            ctx.setFillColor(color.withAlphaComponent(grainOpacity * brush.opacity).cgColor)
            ctx.fillEllipse(in: CGRect(x: px - particleSize, y: py - particleSize,
                                        width: particleSize * 2, height: particleSize * 2))
        }
    }

    // MARK: - Spray Brush (Particle scatter)

    private func renderSprayStroke(points: [StrokePoint], brush: BrushPreset,
                                    color: NSColor, into ctx: CGContext) {
        let interpolated = StrokeInterpolator.catmullRom(points: points, segmentsPerCurve: 4)
        guard interpolated.count >= 2 else { return }

        var distAccum: CGFloat = 0

        for i in 1..<interpolated.count {
            let prev = interpolated[i - 1]
            let curr = interpolated[i]
            let dist = distance(prev.location, curr.location)
            distAccum += dist

            let radius = brush.radiusForPressure(curr.pressure)
            let spacingDist = max(radius * 2 * brush.spacing, 1)

            while distAccum >= spacingDist {
                distAccum -= spacingDist
                let t = dist > 0 ? (1 - distAccum / dist).clamped(to: 0...1) : 1
                let dabCenter = lerp(prev.location, curr.location, t: t)
                let dabPressure = lerp(prev.pressure, curr.pressure, t: t)
                let dabRadius = brush.radiusForPressure(dabPressure)

                stampSprayDab(at: dabCenter, radius: dabRadius,
                              pressure: dabPressure, brush: brush,
                              color: color, into: ctx)
            }
        }
    }

    private func stampSprayDab(at center: CGPoint, radius: CGFloat,
                                pressure: CGFloat, brush: BrushPreset,
                                color: NSColor, into ctx: CGContext) {
        let count = Int(CGFloat(brush.particleDensity) * pressure * brush.scatter)
        let particleRadius: CGFloat = max(radius * 0.03, 0.5)

        let dabColor = color.withAlphaComponent(brush.flow * brush.opacity)
        ctx.setFillColor(dabColor.cgColor)

        for _ in 0..<count {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let dist = radius * sqrt(CGFloat.random(in: 0...1))
            let px = center.x + cos(angle) * dist
            let py = center.y + sin(angle) * dist

            let pr = particleRadius * CGFloat.random(in: 0.5...1.5)
            ctx.fillEllipse(in: CGRect(x: px - pr, y: py - pr,
                                        width: pr * 2, height: pr * 2))
        }
    }
}
