import CoreImage
import CoreGraphics

struct EffectRenderer {

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Apply all enabled effects to a layer image. Returns a new image with effects composited.
    /// The returned image may be larger than the input (to accommodate shadow/glow offsets).
    static func applyEffects(_ effects: LayerEffects, to image: CGImage) -> CGImage? {
        let w = image.width
        let h = image.height

        // Calculate expansion needed for effects that extend beyond the layer bounds
        let expand = expansionNeeded(effects)
        let totalW = w + expand.left + expand.right
        let totalH = h + expand.top + expand.bottom

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let rect = CGRect(x: 0, y: 0, width: totalW, height: totalH)
        let imageRect = CGRect(x: expand.left, y: expand.bottom, width: w, height: h)

        guard let ctx = CGContext(
            data: nil, width: totalW, height: totalH,
            bitsPerComponent: 8, bytesPerRow: totalW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        ctx.clear(rect)

        // Rendering order (bottom to top):
        // 1. Drop shadow (behind layer)
        // 2. Outer glow (behind layer)
        // 3. Original layer image
        // 4. Stroke (around boundary)
        // 5. Inner shadow (inside layer)

        if let shadow = effects.dropShadow {
            renderDropShadow(shadow, image: image, into: ctx, imageRect: imageRect)
        }

        if let glow = effects.outerGlow {
            renderOuterGlow(glow, image: image, into: ctx, imageRect: imageRect)
        }

        // Draw the original layer
        ctx.draw(image, in: imageRect)

        if let stroke = effects.stroke {
            renderStroke(stroke, image: image, into: ctx, imageRect: imageRect)
        }

        if let innerShadow = effects.innerShadow {
            renderInnerShadow(innerShadow, image: image, into: ctx, imageRect: imageRect)
        }

        return ctx.makeImage()
    }

    /// Returns the pixel expansion needed around the layer to fit all effects.
    static func expansionNeeded(_ effects: LayerEffects) -> (left: Int, right: Int, top: Int, bottom: Int) {
        var left = 0, right = 0, top = 0, bottom = 0

        if let s = effects.dropShadow {
            let pad = Int(ceil(s.blurRadius * 2))
            let ox = Int(ceil(abs(s.offsetX)))
            let oy = Int(ceil(abs(s.offsetY)))
            left = max(left, pad + (s.offsetX < 0 ? ox : 0))
            right = max(right, pad + (s.offsetX > 0 ? ox : 0))
            top = max(top, pad + (s.offsetY < 0 ? oy : 0))
            bottom = max(bottom, pad + (s.offsetY > 0 ? oy : 0))
        }

        if let g = effects.outerGlow {
            let pad = Int(ceil(g.blurRadius * 2))
            left = max(left, pad)
            right = max(right, pad)
            top = max(top, pad)
            bottom = max(bottom, pad)
        }

        if let st = effects.stroke, st.position != .inside {
            let pad = Int(ceil(st.width))
            left = max(left, pad)
            right = max(right, pad)
            top = max(top, pad)
            bottom = max(bottom, pad)
        }

        return (left, right, top, bottom)
    }

    // MARK: - Drop Shadow

    private static func renderDropShadow(_ shadow: DropShadowEffect, image: CGImage,
                                          into ctx: CGContext, imageRect: CGRect) {
        // Extract alpha, blur it, colorize, offset, draw
        guard let alpha = extractAlpha(from: image) else { return }

        let ciAlpha = CIImage(cgImage: alpha)
        let clamped = ciAlpha.clampedToExtent()

        guard let blur = CIFilter(name: "CIGaussianBlur") else { return }
        blur.setValue(clamped, forKey: kCIInputImageKey)
        blur.setValue(shadow.blurRadius, forKey: kCIInputRadiusKey)
        guard let blurred = blur.outputImage else { return }

        let extent = CGRect(origin: .zero, size: CGSize(width: image.width, height: image.height))
        let padded = extent.insetBy(dx: -shadow.blurRadius * 2, dy: -shadow.blurRadius * 2)
        guard let blurredCG = ciContext.createCGImage(blurred, from: padded,
                                                       format: .RGBA8,
                                                       colorSpace: CGColorSpaceCreateDeviceRGB()) else { return }

        // Colorize: draw shadow color clipped by blurred alpha
        let shadowW = blurredCG.width
        let shadowH = blurredCG.height
        guard let shadowCtx = CGContext(
            data: nil, width: shadowW, height: shadowH,
            bitsPerComponent: 8, bytesPerRow: shadowW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        let shadowRect = CGRect(x: 0, y: 0, width: shadowW, height: shadowH)
        shadowCtx.clear(shadowRect)
        shadowCtx.draw(blurredCG, in: shadowRect)

        // Replace RGB with shadow color, keeping alpha from blur
        shadowCtx.saveGState()
        shadowCtx.setBlendMode(.sourceAtop)
        shadowCtx.setFillColor(shadow.color)
        shadowCtx.fill(shadowRect)
        shadowCtx.restoreGState()

        guard let colorized = shadowCtx.makeImage() else { return }

        // Draw with offset and opacity
        let blurExpand = shadow.blurRadius * 2
        let drawX = imageRect.minX - blurExpand + shadow.offsetX
        // CGContext Y is bottom-up; shadow offsetY positive = down in screen = negative in CG
        let drawY = imageRect.minY - blurExpand - shadow.offsetY
        let drawRect = CGRect(x: drawX, y: drawY,
                              width: CGFloat(shadowW), height: CGFloat(shadowH))

        ctx.saveGState()
        ctx.setAlpha(shadow.opacity)
        ctx.draw(colorized, in: drawRect)
        ctx.restoreGState()
    }

    // MARK: - Outer Glow

    private static func renderOuterGlow(_ glow: OuterGlowEffect, image: CGImage,
                                         into ctx: CGContext, imageRect: CGRect) {
        guard let alpha = extractAlpha(from: image) else { return }

        let ciAlpha = CIImage(cgImage: alpha)
        let clamped = ciAlpha.clampedToExtent()

        guard let blur = CIFilter(name: "CIGaussianBlur") else { return }
        blur.setValue(clamped, forKey: kCIInputImageKey)
        blur.setValue(glow.blurRadius, forKey: kCIInputRadiusKey)
        guard let blurred = blur.outputImage else { return }

        let extent = CGRect(origin: .zero, size: CGSize(width: image.width, height: image.height))
        let padded = extent.insetBy(dx: -glow.blurRadius * 2, dy: -glow.blurRadius * 2)
        guard let blurredCG = ciContext.createCGImage(blurred, from: padded,
                                                       format: .RGBA8,
                                                       colorSpace: CGColorSpaceCreateDeviceRGB()) else { return }

        // Colorize
        let glowW = blurredCG.width
        let glowH = blurredCG.height
        guard let glowCtx = CGContext(
            data: nil, width: glowW, height: glowH,
            bitsPerComponent: 8, bytesPerRow: glowW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        let glowRect = CGRect(x: 0, y: 0, width: glowW, height: glowH)
        glowCtx.clear(glowRect)
        glowCtx.draw(blurredCG, in: glowRect)

        glowCtx.saveGState()
        glowCtx.setBlendMode(.sourceAtop)
        glowCtx.setFillColor(glow.color)
        glowCtx.fill(glowRect)
        glowCtx.restoreGState()

        guard let colorized = glowCtx.makeImage() else { return }

        let blurExpand = glow.blurRadius * 2
        let drawX = imageRect.minX - blurExpand
        let drawY = imageRect.minY - blurExpand
        let drawRect = CGRect(x: drawX, y: drawY,
                              width: CGFloat(glowW), height: CGFloat(glowH))

        ctx.saveGState()
        ctx.setAlpha(glow.opacity)
        ctx.draw(colorized, in: drawRect)
        ctx.restoreGState()
    }

    // MARK: - Stroke

    private static func renderStroke(_ stroke: StrokeEffect, image: CGImage,
                                      into ctx: CGContext, imageRect: CGRect) {
        guard let alpha = extractAlpha(from: image) else { return }

        let ciAlpha = CIImage(cgImage: alpha)

        // Dilate alpha by stroke width using morphology
        guard let dilate = CIFilter(name: "CIMorphologyMaximum") else { return }
        dilate.setValue(ciAlpha, forKey: kCIInputImageKey)

        let radius: CGFloat
        switch stroke.position {
        case .outside: radius = stroke.width
        case .center: radius = stroke.width / 2
        case .inside: radius = 0  // inside stroke doesn't need dilation
        }

        if stroke.position == .inside {
            // For inside stroke: erode the alpha, subtract from original → stroke mask inside boundary
            renderInsideStroke(stroke, image: image, alpha: alpha, into: ctx, imageRect: imageRect)
            return
        }

        dilate.setValue(radius, forKey: kCIInputRadiusKey)
        guard let dilated = dilate.outputImage else { return }

        let extent = CGRect(origin: .zero, size: CGSize(width: image.width, height: image.height))
        let padded = extent.insetBy(dx: -stroke.width, dy: -stroke.width)
        guard let dilatedCG = ciContext.createCGImage(dilated, from: padded,
                                                       format: .RGBA8,
                                                       colorSpace: CGColorSpaceCreateDeviceRGB()) else { return }

        // Create stroke-only mask: dilated minus original
        let strokeW = dilatedCG.width
        let strokeH = dilatedCG.height
        guard let strokeCtx = CGContext(
            data: nil, width: strokeW, height: strokeH,
            bitsPerComponent: 8, bytesPerRow: strokeW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        let strokeRect = CGRect(x: 0, y: 0, width: strokeW, height: strokeH)
        strokeCtx.clear(strokeRect)

        // Draw dilated
        strokeCtx.draw(dilatedCG, in: strokeRect)

        // Subtract original alpha (destinationOut)
        strokeCtx.saveGState()
        strokeCtx.setBlendMode(.destinationOut)
        let insetRect = CGRect(x: stroke.width, y: stroke.width,
                               width: CGFloat(image.width), height: CGFloat(image.height))
        strokeCtx.draw(alpha, in: insetRect)
        strokeCtx.restoreGState()

        // Colorize
        strokeCtx.saveGState()
        strokeCtx.setBlendMode(.sourceAtop)
        strokeCtx.setFillColor(stroke.color)
        strokeCtx.fill(strokeRect)
        strokeCtx.restoreGState()

        guard let colorized = strokeCtx.makeImage() else { return }

        let drawX = imageRect.minX - stroke.width
        let drawY = imageRect.minY - stroke.width
        let drawRect = CGRect(x: drawX, y: drawY,
                              width: CGFloat(strokeW), height: CGFloat(strokeH))

        ctx.saveGState()
        ctx.setAlpha(stroke.opacity)
        ctx.draw(colorized, in: drawRect)
        ctx.restoreGState()
    }

    private static func renderInsideStroke(_ stroke: StrokeEffect, image: CGImage,
                                            alpha: CGImage, into ctx: CGContext, imageRect: CGRect) {
        let w = image.width
        let h = image.height

        // Erode alpha
        let ciAlpha = CIImage(cgImage: alpha)
        guard let erode = CIFilter(name: "CIMorphologyMinimum") else { return }
        erode.setValue(ciAlpha, forKey: kCIInputImageKey)
        erode.setValue(stroke.width, forKey: kCIInputRadiusKey)
        guard let eroded = erode.outputImage else { return }

        let extent = CGRect(origin: .zero, size: CGSize(width: w, height: h))
        guard let erodedCG = ciContext.createCGImage(eroded, from: extent,
                                                      format: .RGBA8,
                                                      colorSpace: CGColorSpaceCreateDeviceRGB()) else { return }

        // Stroke mask = original alpha - eroded alpha
        guard let strokeCtx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        strokeCtx.clear(rect)
        strokeCtx.draw(alpha, in: rect)

        strokeCtx.saveGState()
        strokeCtx.setBlendMode(.destinationOut)
        strokeCtx.draw(erodedCG, in: rect)
        strokeCtx.restoreGState()

        // Colorize
        strokeCtx.saveGState()
        strokeCtx.setBlendMode(.sourceAtop)
        strokeCtx.setFillColor(stroke.color)
        strokeCtx.fill(rect)
        strokeCtx.restoreGState()

        guard let colorized = strokeCtx.makeImage() else { return }

        ctx.saveGState()
        ctx.setAlpha(stroke.opacity)
        ctx.draw(colorized, in: imageRect)
        ctx.restoreGState()
    }

    // MARK: - Inner Shadow

    private static func renderInnerShadow(_ innerShadow: InnerShadowEffect, image: CGImage,
                                            into ctx: CGContext, imageRect: CGRect) {
        let w = image.width
        let h = image.height

        // 1. Invert the alpha channel
        guard let alpha = extractAlpha(from: image) else { return }

        let ciAlpha = CIImage(cgImage: alpha)
        guard let invert = CIFilter(name: "CIColorInvert") else { return }
        invert.setValue(ciAlpha, forKey: kCIInputImageKey)
        guard let inverted = invert.outputImage else { return }

        // 2. Blur the inverted alpha
        let clamped = inverted.clampedToExtent()
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return }
        blur.setValue(clamped, forKey: kCIInputImageKey)
        blur.setValue(innerShadow.blurRadius, forKey: kCIInputRadiusKey)
        guard let blurred = blur.outputImage else { return }

        // 3. Offset
        let offset = CGAffineTransform(translationX: innerShadow.offsetX, y: -innerShadow.offsetY)
        let shifted = blurred.transformed(by: offset)

        let extent = CGRect(origin: .zero, size: CGSize(width: w, height: h))
        guard let blurredCG = ciContext.createCGImage(shifted, from: extent,
                                                       format: .RGBA8,
                                                       colorSpace: CGColorSpaceCreateDeviceRGB()) else { return }

        // 4. Clip to original alpha (sourceAtop) and colorize
        guard let shadowCtx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        shadowCtx.clear(rect)

        // Draw original alpha as base
        shadowCtx.draw(alpha, in: rect)

        // Draw blurred inverted alpha clipped to original (sourceAtop)
        shadowCtx.saveGState()
        shadowCtx.setBlendMode(.sourceAtop)
        shadowCtx.draw(blurredCG, in: rect)
        shadowCtx.restoreGState()

        // Colorize
        shadowCtx.saveGState()
        shadowCtx.setBlendMode(.sourceAtop)
        shadowCtx.setFillColor(innerShadow.color)
        shadowCtx.fill(rect)
        shadowCtx.restoreGState()

        guard let colorized = shadowCtx.makeImage() else { return }

        ctx.saveGState()
        ctx.setAlpha(innerShadow.opacity)
        ctx.draw(colorized, in: imageRect)
        ctx.restoreGState()
    }

    // MARK: - Alpha Extraction

    /// Extract the alpha channel as an RGBA image (white pixels with varying alpha).
    private static func extractAlpha(from image: CGImage) -> CGImage? {
        let w = image.width
        let h = image.height
        let bytesPerRow = w * 4

        // Read source pixels
        guard let srcCtx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let srcData = srcCtx.data else { return nil }
        srcCtx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Create alpha-only RGBA: white pixels with original alpha
        guard let dstCtx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let dstData = dstCtx.data else { return nil }
        dstCtx.clear(CGRect(x: 0, y: 0, width: w, height: h))

        let src = srcData.bindMemory(to: UInt8.self, capacity: h * bytesPerRow)
        let dst = dstData.bindMemory(to: UInt8.self, capacity: h * bytesPerRow)

        for i in stride(from: 0, to: h * bytesPerRow, by: 4) {
            let a = src[i + 3]
            dst[i]     = a  // premultiplied R
            dst[i + 1] = a  // premultiplied G
            dst[i + 2] = a  // premultiplied B
            dst[i + 3] = a  // A
        }

        return dstCtx.makeImage()
    }
}
