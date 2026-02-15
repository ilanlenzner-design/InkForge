import Foundation
import CoreGraphics
import AppKit

class Layer {
    let id: UUID = UUID()
    var name: String
    var isVisible: Bool = true
    var opacity: CGFloat = 1.0
    var blendMode: CGBlendMode = .normal
    var isLocked: Bool = false
    var isAlphaLocked: Bool = false
    var isClippingMask: Bool = false
    var isReferenceLayer: Bool = false
    var effects = LayerEffects() {
        didSet { invalidateEffectsCache() }
    }
    private(set) var context: CGContext
    private var savedAlpha: [UInt8]?
    let size: CGSize

    // MARK: - Effects Cache
    private var _cachedEffectsImage: CGImage?
    private var _cachedEffectsExpand: (left: Int, right: Int, top: Int, bottom: Int)?
    private(set) var effectsCacheDirty = true

    func invalidateEffectsCache() {
        _cachedEffectsImage = nil
        _cachedEffectsExpand = nil
        effectsCacheDirty = true
    }

    /// Returns a cached effects-applied image. Computes once, then returns the cached version
    /// until content or effects change.
    func cachedEffectsImage() -> (image: CGImage, expand: (left: Int, right: Int, top: Int, bottom: Int))? {
        guard effects.hasAny else { return nil }
        if !effectsCacheDirty, let img = _cachedEffectsImage, let exp = _cachedEffectsExpand {
            return (img, exp)
        }
        guard let base = makeImage() else { return nil }
        let expand = EffectRenderer.expansionNeeded(effects)
        guard let result = EffectRenderer.applyEffects(effects, to: base) else { return nil }
        _cachedEffectsImage = result
        _cachedEffectsExpand = expand
        effectsCacheDirty = false
        return (result, expand)
    }

    // MARK: - Text Layer
    private var _textContent: TextContent?
    var textContent: TextContent? {
        get { _textContent }
        set {
            _textContent = newValue
            if newValue != nil { renderTextContent() }
        }
    }
    var isTextLayer: Bool { _textContent != nil }

    // MARK: - Layer Mask
    private(set) var maskContext: CGContext?
    var isMaskEditing: Bool = false
    var hasMask: Bool { maskContext != nil }

    /// Returns the context tools should draw into: mask when editing, otherwise layer content.
    var drawingContext: CGContext {
        if isMaskEditing, let mask = maskContext { return mask }
        return context
    }

    init(name: String, size: CGSize) {
        self.name = name
        self.size = size

        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        self.context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        // No flip - keep default bottom-left origin.
        // We'll flip when drawing into this context and when displaying.
        context.clear(CGRect(origin: .zero, size: size))
    }

    func makeImage() -> CGImage? {
        return context.makeImage()
    }

    func restoreFromImage(_ image: CGImage) {
        context.saveGState()
        context.concatenate(context.ctm.inverted())
        context.clear(CGRect(x: 0, y: 0, width: Int(size.width), height: Int(size.height)))
        context.draw(image, in: CGRect(x: 0, y: 0, width: Int(size.width), height: Int(size.height)))
        context.restoreGState()
        invalidateEffectsCache()
    }

    func clear() {
        context.clear(CGRect(origin: .zero, size: size))
        invalidateEffectsCache()
    }

    func fillWith(color: NSColor) {
        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        invalidateEffectsCache()
    }

    // MARK: - Mask Operations

    func createMask() {
        let width = Int(size.width)
        let height = Int(size.height)
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        // Fill white = fully visible
        ctx.setFillColor(gray: 1.0, alpha: 1.0)
        ctx.fill(CGRect(origin: .zero, size: size))
        maskContext = ctx
    }

    func deleteMask() {
        maskContext = nil
        isMaskEditing = false
        invalidateEffectsCache()
    }

    func makeMaskImage() -> CGImage? {
        return maskContext?.makeImage()
    }

    func restoreMaskFromImage(_ image: CGImage) {
        guard let ctx = maskContext else { return }
        ctx.saveGState()
        ctx.concatenate(ctx.ctm.inverted())
        ctx.clear(CGRect(origin: .zero, size: size))
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        ctx.restoreGState()
        invalidateEffectsCache()
    }

    /// Prepare context for drawing in top-left (flipped) coordinates, matching the canvas view.
    /// When alpha lock is on, saves alpha channel to restore after drawing.
    /// Optional selection mask clips drawing to selected region.
    func beginDrawing(clippingTo selection: SelectionMask? = nil) {
        let ctx = drawingContext

        // Alpha lock only applies to content context, not mask (masks have no alpha channel)
        if isAlphaLocked && !isMaskEditing {
            saveAlphaChannel()
        }

        ctx.saveGState()

        // Apply selection clipping BEFORE the coordinate flip (native bottom-left coords).
        if let sel = selection, !sel.isEmpty, let maskImage = sel.makeMaskImage() {
            ctx.clip(to: CGRect(origin: .zero, size: size), mask: maskImage)
        }

        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
    }

    func endDrawing() {
        let ctx = drawingContext
        ctx.restoreGState()

        if isAlphaLocked && !isMaskEditing {
            restoreAlphaChannel()
        }
        invalidateEffectsCache()
    }

    // MARK: - Text Layer Rendering

    /// Clear the bitmap and re-render text from stored parameters.
    func renderTextContent() {
        guard let tc = _textContent else { return }

        context.clear(CGRect(origin: .zero, size: size))

        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        let attrString = tc.attributedString()
        let nsCtx = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        attrString.draw(at: tc.position)
        NSGraphicsContext.restoreGraphicsState()

        context.restoreGState()
        invalidateEffectsCache()
    }

    /// Convert a text layer to a regular pixel layer.
    /// The rendered pixels remain; only textContent metadata is discarded.
    func rasterize() {
        _textContent = nil
    }

    /// Restore textContent without re-rendering (used by undo system).
    func restoreTextContent(_ content: TextContent?) {
        _textContent = content
    }

    // MARK: - Alpha Channel

    private func saveAlphaChannel() {
        guard let data = context.data else { return }
        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerRow = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)

        var alpha = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                alpha[y * width + x] = pixels[y * bytesPerRow + x * 4 + 3]
            }
        }
        savedAlpha = alpha
    }

    private func restoreAlphaChannel() {
        guard let alpha = savedAlpha, let data = context.data else { return }
        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerRow = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)

        for y in 0..<height {
            for x in 0..<width {
                pixels[y * bytesPerRow + x * 4 + 3] = alpha[y * width + x]
            }
        }
        savedAlpha = nil
    }
}
