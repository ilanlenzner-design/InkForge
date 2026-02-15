import Foundation
import CoreGraphics
import AppKit

protocol LayerStackDelegate: AnyObject {
    func layerStackDidChange()
}

class LayerStack {
    private(set) var layers: [Layer] = []
    var activeLayerIndex: Int = 0
    weak var delegate: LayerStackDelegate?

    var activeLayer: Layer? {
        return layers[safe: activeLayerIndex]
    }

    /// Reference layer for fill tool boundary detection (nil = use composite)
    var referenceLayer: Layer? {
        return layers.first(where: { $0.isReferenceLayer && $0.isVisible })
    }

    let canvasSize: CGSize

    init(canvasSize: CGSize) {
        self.canvasSize = canvasSize

        let bg = Layer(name: "Background", size: canvasSize)
        bg.fillWith(color: .white)
        bg.isLocked = true
        layers.append(bg)

        let drawing = Layer(name: "Layer 1", size: canvasSize)
        layers.append(drawing)
        activeLayerIndex = 1
    }

    /// Apply a grayscale mask to an RGBA image: multiply each pixel's alpha by the mask value.
    private func applyMask(image: CGImage, mask: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4

        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        // Draw the layer image
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.draw(image, in: rect)

        // Render mask into a temporary grayscale buffer
        guard let maskCtx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return image }

        maskCtx.draw(mask, in: rect)

        guard let imgData = ctx.data, let maskData = maskCtx.data else { return image }
        let imgPixels = imgData.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)
        let maskPixels = maskData.bindMemory(to: UInt8.self, capacity: height * width)

        for y in 0..<height {
            for x in 0..<width {
                let imgOff = y * bytesPerRow + x * 4
                let maskOff = y * width + x
                let maskVal = UInt16(maskPixels[maskOff])
                let alpha = UInt16(imgPixels[imgOff + 3])
                let newAlpha = UInt8((alpha * maskVal) / 255)
                // Premultiplied: scale RGB by the same factor
                if alpha > 0 {
                    let scale = CGFloat(newAlpha) / CGFloat(alpha)
                    imgPixels[imgOff]     = UInt8(CGFloat(imgPixels[imgOff]) * scale)
                    imgPixels[imgOff + 1] = UInt8(CGFloat(imgPixels[imgOff + 1]) * scale)
                    imgPixels[imgOff + 2] = UInt8(CGFloat(imgPixels[imgOff + 2]) * scale)
                }
                imgPixels[imgOff + 3] = newAlpha
            }
        }

        return ctx.makeImage()
    }

    func compositeImage() -> CGImage? {
        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let rect = CGRect(origin: .zero, size: canvasSize)

        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(rect)

        var i = 0
        while i < layers.count {
            let baseLayer = layers[i]
            guard baseLayer.isVisible else { i += 1; continue }

            // Collect clipping group: base layer + consecutive clipping layers above it
            var clippingGroup: [Layer] = []
            var j = i + 1
            while j < layers.count, layers[j].isClippingMask {
                if layers[j].isVisible {
                    clippingGroup.append(layers[j])
                }
                j += 1
            }

            if clippingGroup.isEmpty {
                // No clipping — draw normally
                if baseLayer.effects.hasAny, !baseLayer.hasMask,
                   let cached = baseLayer.cachedEffectsImage() {
                    // Use cached effects image (fast path)
                    let fxRect = CGRect(x: -CGFloat(cached.expand.left), y: -CGFloat(cached.expand.bottom),
                                        width: CGFloat(cached.image.width), height: CGFloat(cached.image.height))
                    ctx.saveGState()
                    ctx.setAlpha(baseLayer.opacity)
                    ctx.setBlendMode(baseLayer.blendMode)
                    ctx.draw(cached.image, in: fxRect)
                    ctx.restoreGState()
                } else {
                    guard var image = baseLayer.makeImage() else { i += 1; continue }
                    if let maskImg = baseLayer.makeMaskImage() {
                        image = applyMask(image: image, mask: maskImg) ?? image
                    }
                    if baseLayer.effects.hasAny {
                        let expand = EffectRenderer.expansionNeeded(baseLayer.effects)
                        let fxImage = EffectRenderer.applyEffects(baseLayer.effects, to: image) ?? image
                        let fxRect = CGRect(x: -CGFloat(expand.left), y: -CGFloat(expand.bottom),
                                            width: CGFloat(fxImage.width), height: CGFloat(fxImage.height))
                        ctx.saveGState()
                        ctx.setAlpha(baseLayer.opacity)
                        ctx.setBlendMode(baseLayer.blendMode)
                        ctx.draw(fxImage, in: fxRect)
                        ctx.restoreGState()
                    } else {
                        ctx.saveGState()
                        ctx.setAlpha(baseLayer.opacity)
                        ctx.setBlendMode(baseLayer.blendMode)
                        ctx.draw(image, in: rect)
                        ctx.restoreGState()
                    }
                }
            } else {
                // Render base + clipped layers into temp context, then composite
                guard let groupCtx = CGContext(
                    data: nil, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { i = j; continue }

                groupCtx.clear(rect)

                // Draw base layer at full opacity into group
                if var baseImage = baseLayer.makeImage() {
                    if let maskImg = baseLayer.makeMaskImage() {
                        baseImage = applyMask(image: baseImage, mask: maskImg) ?? baseImage
                    }
                    groupCtx.setAlpha(baseLayer.opacity)
                    groupCtx.draw(baseImage, in: rect)
                }

                // Draw each clipped layer using sourceAtop — clips to base alpha
                for clippedLayer in clippingGroup {
                    guard var clippedImage = clippedLayer.makeImage() else { continue }
                    if let maskImg = clippedLayer.makeMaskImage() {
                        clippedImage = applyMask(image: clippedImage, mask: maskImg) ?? clippedImage
                    }
                    groupCtx.saveGState()
                    groupCtx.setAlpha(clippedLayer.opacity)
                    groupCtx.setBlendMode(.sourceAtop)
                    groupCtx.draw(clippedImage, in: rect)
                    groupCtx.restoreGState()
                }

                // Apply effects to the composited group, then draw onto main canvas
                if let groupImage = groupCtx.makeImage() {
                    if baseLayer.effects.hasAny {
                        let expand = EffectRenderer.expansionNeeded(baseLayer.effects)
                        let fxImage = EffectRenderer.applyEffects(baseLayer.effects, to: groupImage) ?? groupImage
                        let fxRect = CGRect(x: -CGFloat(expand.left), y: -CGFloat(expand.bottom),
                                            width: CGFloat(fxImage.width), height: CGFloat(fxImage.height))
                        ctx.saveGState()
                        ctx.setBlendMode(baseLayer.blendMode)
                        ctx.draw(fxImage, in: fxRect)
                        ctx.restoreGState()
                    } else {
                        ctx.saveGState()
                        ctx.setBlendMode(baseLayer.blendMode)
                        ctx.draw(groupImage, in: rect)
                        ctx.restoreGState()
                    }
                }
            }

            i = j
        }

        return ctx.makeImage()
    }

    @discardableResult
    func addLayer(name: String? = nil) -> Layer {
        let n = name ?? "Layer \(layers.count)"
        let layer = Layer(name: n, size: canvasSize)
        layers.insert(layer, at: activeLayerIndex + 1)
        activeLayerIndex += 1
        delegate?.layerStackDidChange()
        return layer
    }

    @discardableResult
    func addLayerFromImage(_ image: CGImage, name: String) -> Layer {
        let layer = Layer(name: name, size: canvasSize)

        // Draw image centered, scaled to fit canvas while maintaining aspect ratio
        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        let scaleX = canvasSize.width / imgW
        let scaleY = canvasSize.height / imgH
        let scale = min(scaleX, scaleY, 1.0)  // Don't upscale

        let drawW = imgW * scale
        let drawH = imgH * scale
        let drawX = (canvasSize.width - drawW) / 2
        let drawY = (canvasSize.height - drawH) / 2

        layer.context.draw(image, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))

        layers.insert(layer, at: activeLayerIndex + 1)
        activeLayerIndex += 1
        delegate?.layerStackDidChange()
        return layer
    }

    @discardableResult
    func addTextLayer(content: TextContent) -> Layer {
        let preview = content.text.prefix(20)
        let layer = Layer(name: "Text: \(preview)", size: canvasSize)
        layer.textContent = content
        layers.insert(layer, at: activeLayerIndex + 1)
        activeLayerIndex += 1
        delegate?.layerStackDidChange()
        return layer
    }

    func rasterizeLayer(at index: Int) {
        guard let layer = layers[safe: index], layer.isTextLayer else { return }
        layer.rasterize()
        delegate?.layerStackDidChange()
    }

    /// Remove a layer by index (used by undo system). No guards — caller is responsible.
    func removeLayerForUndo(at index: Int) {
        layers.remove(at: index)
        activeLayerIndex = min(activeLayerIndex, layers.count - 1)
    }

    /// Insert a layer at index (used by undo system). No guards — caller is responsible.
    func insertLayerForUndo(_ layer: Layer, at index: Int) {
        let idx = min(index, layers.count)
        layers.insert(layer, at: idx)
        activeLayerIndex = idx
    }

    func setOpacity(_ opacity: CGFloat, at index: Int) {
        guard let layer = layers[safe: index] else { return }
        layer.opacity = opacity.clamped(to: 0...1)
        delegate?.layerStackDidChange()
    }

    func deleteLayer(at index: Int) {
        guard layers.count > 1 else { return }
        guard !layers[index].isLocked else { return }
        layers.remove(at: index)
        activeLayerIndex = min(activeLayerIndex, layers.count - 1)
        delegate?.layerStackDidChange()
    }

    func moveLayer(from src: Int, to dst: Int) {
        guard src != dst else { return }
        let layer = layers.remove(at: src)
        layers.insert(layer, at: dst)
        if activeLayerIndex == src {
            activeLayerIndex = dst
        }
        delegate?.layerStackDidChange()
    }

    func toggleVisibility(at index: Int) {
        layers[safe: index]?.isVisible.toggle()
        delegate?.layerStackDidChange()
    }

    func mergeDown(at index: Int) {
        guard index > 0, index < layers.count else { return }
        let upper = layers[index]
        let lower = layers[index - 1]

        // Auto-rasterize text layers before merging
        upper.rasterize()
        lower.rasterize()

        guard var upperImage = upper.makeImage() else { return }

        // Apply mask to upper layer before merging
        if let maskImg = upper.makeMaskImage() {
            upperImage = applyMask(image: upperImage, mask: maskImg) ?? upperImage
        }

        // Bake effects into merged result
        if upper.effects.hasAny {
            upperImage = EffectRenderer.applyEffects(upper.effects, to: upperImage) ?? upperImage
            let expand = EffectRenderer.expansionNeeded(upper.effects)
            let fxRect = CGRect(x: -CGFloat(expand.left), y: -CGFloat(expand.bottom),
                                width: CGFloat(upperImage.width), height: CGFloat(upperImage.height))
            lower.context.saveGState()
            lower.context.setAlpha(upper.opacity)
            lower.context.setBlendMode(upper.blendMode)
            lower.context.draw(upperImage, in: fxRect)
            lower.context.restoreGState()
        } else {
            lower.context.saveGState()
            lower.context.setAlpha(upper.opacity)
            lower.context.setBlendMode(upper.blendMode)
            lower.context.draw(upperImage, in: CGRect(origin: .zero, size: canvasSize))
            lower.context.restoreGState()
        }

        layers.remove(at: index)
        activeLayerIndex = index - 1
        delegate?.layerStackDidChange()
    }
}
