import Foundation
import CoreGraphics

enum SelectionMode {
    case new
    case add
    case subtract
}

class SelectionMask {
    let width: Int
    let height: Int
    private(set) var data: [UInt8]

    private var cachedAntsPath: CGPath?
    private var cachedSimplifiedAntsPath: CGPath?
    private var cachedMaskImage: CGImage?
    private var cachedInvertedMaskImage: CGImage?
    private var pathDirty = true
    private var maskImageDirty = true

    private func invalidateCaches() {
        pathDirty = true
        maskImageDirty = true
    }

    var isEmpty: Bool {
        return !data.contains(where: { $0 > 0 })
    }

    var bounds: CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                if data[y * width + x] > 0 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.data = [UInt8](repeating: 0, count: width * height)
    }

    /// Create a selection mask from a grayscale CGImage (white = selected).
    static func fromMaskImage(_ image: CGImage, width: Int, height: Int) -> SelectionMask? {
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let pixelData = ctx.data else { return nil }
        let pixels = pixelData.bindMemory(to: UInt8.self, capacity: width * height)

        let mask = SelectionMask(width: width, height: height)
        for i in 0..<(width * height) {
            mask.data[i] = pixels[i] > 127 ? 255 : 0
        }
        return mask
    }

    func selectAll() {
        for i in 0..<data.count { data[i] = 255 }
        invalidateCaches()
    }

    func clear() {
        for i in 0..<data.count { data[i] = 0 }
        invalidateCaches()
    }

    func invert() {
        for i in 0..<data.count { data[i] = 255 - data[i] }
        invalidateCaches()
    }

    func isSelected(x: Int, y: Int) -> Bool {
        guard x >= 0, x < width, y >= 0, y < height else { return false }
        return data[y * width + x] > 0
    }

    // MARK: - Shape Selection

    func selectRect(_ rect: CGRect, mode: SelectionMode) {
        if mode == .new { clear() }

        let minX = max(0, Int(floor(rect.minX)))
        let minY = max(0, Int(floor(rect.minY)))
        let maxX = min(width - 1, Int(ceil(rect.maxX)) - 1)
        let maxY = min(height - 1, Int(ceil(rect.maxY)) - 1)
        guard minX <= maxX, minY <= maxY else { invalidateCaches(); return }

        let value: UInt8 = mode == .subtract ? 0 : 255
        for y in minY...maxY {
            for x in minX...maxX {
                data[y * width + x] = value
            }
        }
        invalidateCaches()
    }

    func selectEllipse(_ rect: CGRect, mode: SelectionMode) {
        if mode == .new { clear() }

        let cx = rect.midX
        let cy = rect.midY
        let rx = rect.width / 2
        let ry = rect.height / 2
        guard rx > 0, ry > 0 else { invalidateCaches(); return }

        let minX = max(0, Int(floor(rect.minX)))
        let minY = max(0, Int(floor(rect.minY)))
        let maxX = min(width - 1, Int(ceil(rect.maxX)))
        let maxY = min(height - 1, Int(ceil(rect.maxY)))

        let value: UInt8 = mode == .subtract ? 0 : 255
        for y in minY...maxY {
            for x in minX...maxX {
                let dx = (CGFloat(x) + 0.5 - cx) / rx
                let dy = (CGFloat(y) + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1.0 {
                    data[y * width + x] = value
                }
            }
        }
        invalidateCaches()
    }

    func selectPolygon(_ points: [CGPoint], mode: SelectionMode) {
        if mode == .new { clear() }
        guard points.count >= 3 else { invalidateCaches(); return }

        let ys = points.map { $0.y }
        let minY = max(0, Int(ys.min()!))
        let maxY = min(height - 1, Int(ys.max()!))

        let value: UInt8 = mode == .subtract ? 0 : 255

        for y in minY...maxY {
            let scanY = CGFloat(y) + 0.5
            var intersections: [CGFloat] = []

            for i in 0..<points.count {
                let p1 = points[i]
                let p2 = points[(i + 1) % points.count]

                if (p1.y <= scanY && p2.y > scanY) || (p2.y <= scanY && p1.y > scanY) {
                    let t = (scanY - p1.y) / (p2.y - p1.y)
                    intersections.append(p1.x + t * (p2.x - p1.x))
                }
            }

            intersections.sort()

            var i = 0
            while i + 1 < intersections.count {
                let xStart = max(0, Int(intersections[i]))
                let xEnd = min(width - 1, Int(intersections[i + 1]))
                if xStart <= xEnd {
                    for x in xStart...xEnd {
                        data[y * width + x] = value
                    }
                }
                i += 2
            }
        }
        invalidateCaches()
    }

    func magicWand(at point: CGPoint, compositeData: UnsafePointer<UInt8>,
                   bytesPerRow: Int, tolerance: Int, mode: SelectionMode) {
        if mode == .new { clear() }

        let startX = Int(point.x)
        let startY = Int(point.y)
        guard startX >= 0, startX < width, startY >= 0, startY < height else { return }

        let targetOff = startY * bytesPerRow + startX * 4
        let tR = compositeData[targetOff]
        let tG = compositeData[targetOff + 1]
        let tB = compositeData[targetOff + 2]
        let tA = compositeData[targetOff + 3]

        let value: UInt8 = mode == .subtract ? 0 : 255

        var visited = [Bool](repeating: false, count: width * height)
        var stack: [(Int, Int)] = [(startX, startY)]
        visited[startY * width + startX] = true

        while !stack.isEmpty {
            let (sx, sy) = stack.removeLast()

            var left = sx
            while left > 0 {
                let idx = sy * width + (left - 1)
                if visited[idx] { break }
                let off = sy * bytesPerRow + (left - 1) * 4
                if !matchColor(compositeData, off, tR, tG, tB, tA, tolerance) { break }
                left -= 1
            }

            var right = sx
            while right < width - 1 {
                let idx = sy * width + (right + 1)
                if visited[idx] { break }
                let off = sy * bytesPerRow + (right + 1) * 4
                if !matchColor(compositeData, off, tR, tG, tB, tA, tolerance) { break }
                right += 1
            }

            var aboveAdded = false
            var belowAdded = false

            for x in left...right {
                let idx = sy * width + x
                visited[idx] = true
                data[idx] = value

                if sy > 0 {
                    let ai = (sy - 1) * width + x
                    if !visited[ai] {
                        let aOff = (sy - 1) * bytesPerRow + x * 4
                        let m = matchColor(compositeData, aOff, tR, tG, tB, tA, tolerance)
                        if m && !aboveAdded { stack.append((x, sy - 1)); aboveAdded = true }
                        if !m { aboveAdded = false }
                    }
                }

                if sy < height - 1 {
                    let bi = (sy + 1) * width + x
                    if !visited[bi] {
                        let bOff = (sy + 1) * bytesPerRow + x * 4
                        let m = matchColor(compositeData, bOff, tR, tG, tB, tA, tolerance)
                        if m && !belowAdded { stack.append((x, sy + 1)); belowAdded = true }
                        if !m { belowAdded = false }
                    }
                }
            }
        }
        invalidateCaches()
    }

    private func matchColor(_ d: UnsafePointer<UInt8>, _ off: Int,
                            _ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8,
                            _ tol: Int) -> Bool {
        return abs(Int(d[off]) - Int(r)) <= tol &&
               abs(Int(d[off+1]) - Int(g)) <= tol &&
               abs(Int(d[off+2]) - Int(b)) <= tol &&
               abs(Int(d[off+3]) - Int(a)) <= tol
    }

    // MARK: - Mask Image for Clipping

    /// Creates a CGImage mask for CGContext.clip(to:mask:).
    /// Data is copied directly — both SelectionMask and CGBitmapContext store top-to-bottom.
    func makeMaskImage() -> CGImage? {
        guard !isEmpty else { return nil }
        if !maskImageDirty, let cached = cachedMaskImage { return cached }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let ctxData = ctx.data else { return nil }

        let dst = ctxData.bindMemory(to: UInt8.self, capacity: width * height)
        _ = data.withUnsafeBufferPointer { ptr in
            memcpy(dst, ptr.baseAddress!, width * height)
        }

        let image = ctx.makeImage()
        cachedMaskImage = image
        cachedInvertedMaskImage = nil  // invalidate inverted cache too
        maskImageDirty = false
        return image
    }

    func makeInvertedMaskImage() -> CGImage? {
        if let cached = cachedInvertedMaskImage { return cached }
        guard let maskImage = makeMaskImage() else { return nil }

        let w = maskImage.width
        let h = maskImage.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.draw(maskImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        if let data = ctx.data {
            let pixels = data.bindMemory(to: UInt8.self, capacity: w * h)
            for i in 0..<(w * h) {
                pixels[i] = 255 - pixels[i]
            }
        }

        let inverted = ctx.makeImage()
        cachedInvertedMaskImage = inverted
        return inverted
    }

    // MARK: - Marching Ants Path

    /// Returns a simplified CGPath for marching ants display.
    /// Downsamples the mask by the given factor to reduce path complexity.
    /// On a 2048x2048 canvas with factor=4, this produces ~16x fewer segments.
    func simplifiedAntsPath(downsample ds: Int = 4) -> CGPath {
        if !pathDirty, let cached = cachedSimplifiedAntsPath { return cached }

        let dsW = (width + ds - 1) / ds
        let dsH = (height + ds - 1) / ds

        // Downsample: a cell is "selected" if any pixel in the block is selected
        var dsData = [UInt8](repeating: 0, count: dsW * dsH)
        for dy in 0..<dsH {
            for dx in 0..<dsW {
                let srcX = min(dx * ds + ds / 2, width - 1)
                let srcY = min(dy * ds + ds / 2, height - 1)
                dsData[dy * dsW + dx] = data[srcY * width + srcX]
            }
        }

        let path = CGMutablePath()
        let scale = CGFloat(ds)

        // Horizontal edges
        for y in 0...dsH {
            var startX: Int? = nil
            for x in 0..<dsW {
                let above = y > 0 && dsData[(y-1) * dsW + x] > 0
                let below = y < dsH && dsData[y * dsW + x] > 0
                let isEdge = above != below

                if isEdge {
                    if startX == nil { startX = x }
                } else {
                    if let sx = startX {
                        path.move(to: CGPoint(x: CGFloat(sx) * scale, y: CGFloat(y) * scale))
                        path.addLine(to: CGPoint(x: CGFloat(x) * scale, y: CGFloat(y) * scale))
                        startX = nil
                    }
                }
            }
            if let sx = startX {
                path.move(to: CGPoint(x: CGFloat(sx) * scale, y: CGFloat(y) * scale))
                path.addLine(to: CGPoint(x: CGFloat(dsW) * scale, y: CGFloat(y) * scale))
            }
        }

        // Vertical edges
        for x in 0...dsW {
            var startY: Int? = nil
            for y in 0..<dsH {
                let left = x > 0 && dsData[y * dsW + (x-1)] > 0
                let right = x < dsW && dsData[y * dsW + x] > 0
                let isEdge = left != right

                if isEdge {
                    if startY == nil { startY = y }
                } else {
                    if let sy = startY {
                        path.move(to: CGPoint(x: CGFloat(x) * scale, y: CGFloat(sy) * scale))
                        path.addLine(to: CGPoint(x: CGFloat(x) * scale, y: CGFloat(y) * scale))
                        startY = nil
                    }
                }
            }
            if let sy = startY {
                path.move(to: CGPoint(x: CGFloat(x) * scale, y: CGFloat(sy) * scale))
                path.addLine(to: CGPoint(x: CGFloat(x) * scale, y: CGFloat(dsH) * scale))
            }
        }

        cachedSimplifiedAntsPath = path
        cachedAntsPath = path  // also update full-res cache to same
        pathDirty = false
        return path
    }

    /// Full-resolution path (kept for backward compat but prefer simplifiedAntsPath for display).
    func marchingAntsPath() -> CGPath {
        return simplifiedAntsPath(downsample: 4)
    }
}
