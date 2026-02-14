import AppKit

class NeumorphicVerticalSlider: NSControl {

    var value: CGFloat = 0.5 {
        didSet {
            let range = maxValue - minValue
            value = range > 0 ? value.clamped(to: minValue...maxValue) : minValue
            needsDisplay = true
        }
    }
    var minValue: CGFloat = 0
    var maxValue: CGFloat = 1

    private var isDragging = false

    private let trackWidth: CGFloat = 6
    private let thumbDiameter: CGFloat = 18
    private let trackPadY: CGFloat = 12

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 36, height: NSView.noIntrinsicMetric)
    }

    // Track rect (centered, vertical)
    private var trackRect: CGRect {
        let x = (bounds.width - trackWidth) / 2
        return CGRect(x: x, y: trackPadY,
                      width: trackWidth, height: bounds.height - trackPadY * 2)
    }

    private var normalizedValue: CGFloat {
        let range = maxValue - minValue
        return range > 0 ? (value - minValue) / range : 0
    }

    // In flipped view: norm=1 → top (small y), norm=0 → bottom (large y)
    private var thumbY: CGFloat {
        let track = trackRect
        return track.maxY - normalizedValue * track.height
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let track = trackRect
        let thumbRadius = thumbDiameter / 2
        let thumbCenterY = thumbY
        let cx = bounds.midX
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // --- 1. Track groove (recessed) ---
        let trackPath = CGPath(roundedRect: track,
                               cornerWidth: trackWidth / 2,
                               cornerHeight: trackWidth / 2,
                               transform: nil)

        // Inset shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                       color: NSColor.black.withAlphaComponent(0.6).cgColor)
        ctx.setFillColor(NSColor.inkInset.cgColor)
        ctx.addPath(trackPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Inner groove highlight (top edge light catch)
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.03).cgColor)
        ctx.setLineWidth(0.5)
        ctx.addPath(trackPath)
        ctx.strokePath()

        // --- 2. Filled portion (accent, from bottom up to thumb) ---
        let fillTop = thumbCenterY
        let fillBottom = track.maxY
        if fillBottom > fillTop {
            let fillRect = CGRect(x: track.origin.x, y: fillTop,
                                  width: track.width, height: fillBottom - fillTop)
            ctx.saveGState()
            ctx.addPath(trackPath)
            ctx.clip()

            // Accent fill
            ctx.setFillColor(NSColor.inkAccent.withAlphaComponent(0.5).cgColor)
            ctx.fill(fillRect)

            // Glow effect
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 6,
                           color: NSColor.inkAccent.withAlphaComponent(0.3).cgColor)
            ctx.setFillColor(NSColor.inkAccent.withAlphaComponent(0.4).cgColor)
            ctx.fill(fillRect)
            ctx.restoreGState()

            ctx.restoreGState()
        }

        // --- 3. Thumb ---
        let thumbRect = CGRect(x: cx - thumbRadius, y: thumbCenterY - thumbRadius,
                               width: thumbDiameter, height: thumbDiameter)

        // Thumb drop shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 4,
                       color: NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.setFillColor(NSColor(white: 0.30, alpha: 1).cgColor)
        ctx.fillEllipse(in: thumbRect)
        ctx.restoreGState()

        // Thumb gradient (metallic convex)
        if let grad = CGGradient(colorsSpace: colorSpace,
                                  colors: [NSColor(white: 0.42, alpha: 1).cgColor,
                                           NSColor(white: 0.24, alpha: 1).cgColor] as CFArray,
                                  locations: [0, 1]) {
            ctx.saveGState()
            ctx.addEllipse(in: thumbRect)
            ctx.clip()
            ctx.drawLinearGradient(grad,
                                    start: CGPoint(x: cx, y: thumbRect.minY),
                                    end: CGPoint(x: cx, y: thumbRect.maxY),
                                    options: [])
            ctx.restoreGState()
        }

        // Thumb accent ring with glow when dragging
        ctx.saveGState()
        if isDragging {
            ctx.setShadow(offset: .zero, blur: 6,
                           color: NSColor.inkAccent.withAlphaComponent(0.5).cgColor)
        }
        ctx.setStrokeColor(NSColor.inkAccent.withAlphaComponent(isDragging ? 0.8 : 0.45).cgColor)
        ctx.setLineWidth(1.5)
        ctx.addEllipse(in: thumbRect.insetBy(dx: 1, dy: 1))
        ctx.strokePath()
        ctx.restoreGState()

        // Thumb center indicator
        let dotSize: CGFloat = 4
        ctx.setFillColor(NSColor.inkAccent.withAlphaComponent(0.6).cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - dotSize / 2, y: thumbCenterY - dotSize / 2,
                                    width: dotSize, height: dotSize))
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        updateValueFromEvent(event)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        updateValueFromEvent(event)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        let range = maxValue - minValue
        let delta = event.scrollingDeltaY * 0.003 * range
        value += delta
        sendAction(action, to: target)
    }

    private func updateValueFromEvent(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let track = trackRect
        // Flipped: top = max, bottom = min
        let norm = (1.0 - (point.y - track.minY) / track.height).clamped(to: 0...1)
        value = minValue + norm * (maxValue - minValue)
        sendAction(action, to: target)
    }
}
