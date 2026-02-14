import AppKit

class KnobControl: NSControl {

    // MARK: - Properties

    var value: CGFloat = 0 {
        didSet {
            value = value.clamped(to: minValue...maxValue)
            needsDisplay = true
        }
    }
    var minValue: CGFloat = 0
    var maxValue: CGFloat = 1
    var defaultValue: CGFloat = 0
    var sensitivity: CGFloat = 0.005
    var label: String = ""
    var formattedValue: String = ""

    private var isDragging = false
    private var lastDragPoint: CGPoint = .zero

    // Arc range: 225° (lower-left) sweeping clockwise to -45° (lower-right) = 270° total
    private let startAngle: CGFloat = 5 * .pi / 4   // 225°
    private let endAngle: CGFloat   = -.pi / 4       // -45°

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        NSSize(width: 160, height: 184)
    }

    override var isFlipped: Bool { true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let knobDiameter: CGFloat = 120
        let knobRadius = knobDiameter / 2
        let centerX = bounds.midX
        let centerY: CGFloat = 80  // view coords center (room for LED dots above)

        let range = maxValue - minValue
        let norm = range > 0 ? (value - minValue) / range : 0
        let valueAngle = startAngle + (endAngle - startAngle) * norm

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // Flip context for CG drawing (NSView is flipped, CG is not)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        let cy = bounds.height - centerY
        let center = CGPoint(x: centerX, y: cy)

        // --- 1. Drop shadow ---
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 10,
                       color: NSColor.black.withAlphaComponent(0.6).cgColor)
        ctx.setFillColor(NSColor(white: 0.18, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: centerX - knobRadius, y: cy - knobRadius,
                                    width: knobDiameter, height: knobDiameter))
        ctx.restoreGState()

        // --- 2. Outer bezel ring (gradient: lighter top → darker bottom) ---
        let bezelWidth: CGFloat = 5
        let outerRect = CGRect(x: centerX - knobRadius, y: cy - knobRadius,
                                width: knobDiameter, height: knobDiameter)
        let innerRadius = knobRadius - bezelWidth
        let innerRect = CGRect(x: centerX - innerRadius, y: cy - innerRadius,
                                width: innerRadius * 2, height: innerRadius * 2)

        if let bezelGrad = CGGradient(colorsSpace: colorSpace,
                                       colors: [NSColor(white: 0.40, alpha: 1).cgColor,
                                                NSColor(white: 0.13, alpha: 1).cgColor] as CFArray,
                                       locations: [0, 1]) {
            ctx.saveGState()
            ctx.addEllipse(in: outerRect)
            ctx.addEllipse(in: innerRect)
            ctx.clip(using: .evenOdd)
            ctx.drawLinearGradient(bezelGrad,
                                    start: CGPoint(x: centerX, y: cy + knobRadius),
                                    end: CGPoint(x: centerX, y: cy - knobRadius),
                                    options: [])
            ctx.restoreGState()
        }

        // Accent glow on bezel when dragging
        if isDragging {
            ctx.saveGState()
            ctx.addEllipse(in: outerRect)
            ctx.addEllipse(in: innerRect)
            ctx.clip(using: .evenOdd)
            ctx.setFillColor(NSColor.inkAccent.withAlphaComponent(0.15).cgColor)
            ctx.fill(outerRect)
            ctx.restoreGState()
        }

        // --- 2b. Inner glow ring (cyan accent ring between bezel and face) ---
        let glowRingRect = innerRect.insetBy(dx: -0.5, dy: -0.5)
        // Glow halo (drawn first, with blur)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 6,
                       color: NSColor.inkAccent.withAlphaComponent(0.45).cgColor)
        ctx.setStrokeColor(NSColor.inkAccent.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(1.5)
        ctx.addEllipse(in: glowRingRect)
        ctx.strokePath()
        ctx.restoreGState()
        // Sharp bright ring on top
        ctx.setStrokeColor(NSColor.inkAccent.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(1.5)
        ctx.addEllipse(in: glowRingRect)
        ctx.strokePath()

        // --- 3. Knob face (radial gradient — convex metallic look) ---
        if let faceGrad = CGGradient(colorsSpace: colorSpace,
                                      colors: [NSColor(white: 0.38, alpha: 1).cgColor,
                                               NSColor(white: 0.26, alpha: 1).cgColor,
                                               NSColor(white: 0.16, alpha: 1).cgColor] as CFArray,
                                      locations: [0, 0.6, 1]) {
            ctx.saveGState()
            ctx.addEllipse(in: innerRect)
            ctx.clip()
            // Offset gradient center upper-left for 3D lighting
            let gradCenter = CGPoint(x: centerX - innerRadius * 0.12,
                                      y: cy + innerRadius * 0.18)
            ctx.drawRadialGradient(faceGrad,
                                    startCenter: gradCenter, startRadius: 0,
                                    endCenter: center, endRadius: innerRadius,
                                    options: [.drawsAfterEndLocation])
            ctx.restoreGState()
        }

        // --- 4. Inner edge shadow ---
        ctx.saveGState()
        ctx.addEllipse(in: innerRect)
        ctx.clip()
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(2.5)
        ctx.addEllipse(in: innerRect.insetBy(dx: -1.25, dy: -1.25))
        ctx.strokePath()
        ctx.restoreGState()

        // --- 5. Specular highlight (subtle upper-left glow) ---
        if let hlGrad = CGGradient(colorsSpace: colorSpace,
                                    colors: [NSColor.white.withAlphaComponent(0.12).cgColor,
                                             NSColor.white.withAlphaComponent(0.0).cgColor] as CFArray,
                                    locations: [0, 1]) {
            ctx.saveGState()
            ctx.addEllipse(in: innerRect)
            ctx.clip()
            let hlCenter = CGPoint(x: centerX - innerRadius * 0.22,
                                    y: cy + innerRadius * 0.35)
            ctx.drawRadialGradient(hlGrad,
                                    startCenter: hlCenter, startRadius: 0,
                                    endCenter: hlCenter, endRadius: innerRadius * 0.6,
                                    options: [])
            ctx.restoreGState()
        }

        // --- 6. LED dots around the track ---
        let dotTrackRadius = knobRadius + 10
        let numDots = 21
        for i in 0..<numDots {
            let frac = CGFloat(i) / CGFloat(numDots - 1)
            let dotAngle = startAngle + (endAngle - startAngle) * frac
            let dotX = centerX + dotTrackRadius * cos(dotAngle)
            let dotY = cy + dotTrackRadius * sin(dotAngle)
            let dotPt = CGPoint(x: dotX, y: dotY)

            let isActive = frac <= norm + 0.001

            if isActive {
                // Glow halo
                if let glowGrad = CGGradient(colorsSpace: colorSpace,
                                              colors: [NSColor.inkAccent.withAlphaComponent(0.4).cgColor,
                                                       NSColor.inkAccent.withAlphaComponent(0.0).cgColor] as CFArray,
                                              locations: [0, 1]) {
                    ctx.drawRadialGradient(glowGrad,
                                            startCenter: dotPt, startRadius: 0,
                                            endCenter: dotPt, endRadius: 8,
                                            options: [])
                }
                // Bright dot
                ctx.setFillColor(NSColor.inkAccent.cgColor)
                ctx.fillEllipse(in: CGRect(x: dotX - 3, y: dotY - 3, width: 6, height: 6))
            } else {
                // Dim dot
                ctx.setFillColor(NSColor(white: 0.22, alpha: 1).cgColor)
                ctx.fillEllipse(in: CGRect(x: dotX - 2, y: dotY - 2, width: 4, height: 4))
            }
        }

        // --- 7. Indicator line on knob face ---
        let lineStart = innerRadius * 0.45
        let lineEnd = innerRadius * 0.82
        let lineAlpha: CGFloat = isDragging ? 1.0 : 0.85
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(lineAlpha).cgColor)
        ctx.setLineWidth(2.5)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: centerX + lineStart * cos(valueAngle),
                              y: cy + lineStart * sin(valueAngle)))
        ctx.addLine(to: CGPoint(x: centerX + lineEnd * cos(valueAngle),
                                 y: cy + lineEnd * sin(valueAngle)))
        ctx.strokePath()

        ctx.restoreGState()

        // --- 8. Value text (centered inside the knob) ---
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.inkText.withAlphaComponent(0.8),
        ]
        let valueStr = NSAttributedString(string: formattedValue, attributes: valueAttrs)
        let valueSize = valueStr.size()
        valueStr.draw(at: NSPoint(x: centerX - valueSize.width / 2,
                                   y: centerY - valueSize.height / 2))

        // --- 9. Label text (below the knob) ---
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.inkTextDim,
        ]
        let labelStr = NSAttributedString(string: label, attributes: labelAttrs)
        let labelSize = labelStr.size()
        labelStr.draw(at: NSPoint(x: centerX - labelSize.width / 2,
                                   y: centerY + knobRadius + 14))
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            value = defaultValue
            sendAction(action, to: target)
            return
        }
        isDragging = true
        lastDragPoint = event.locationInWindow
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let current = event.locationInWindow
        let dx = current.x - lastDragPoint.x
        let dy = current.y - lastDragPoint.y
        let delta = (dx + dy) * sensitivity
        value += delta * (maxValue - minValue)
        lastDragPoint = current
        sendAction(action, to: target)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY * sensitivity * 0.3
        value += delta * (maxValue - minValue)
        sendAction(action, to: target)
    }
}
