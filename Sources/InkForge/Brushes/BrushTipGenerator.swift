import CoreGraphics
import Foundation

struct BrushTipGenerator {

    static let tipSize: Int = 128
    private static let center = CGFloat(tipSize) / 2
    private static let radius = CGFloat(tipSize) / 2

    static func generate(_ tipType: BrushPreset.BrushTipType) -> CGImage? {
        switch tipType {
        case .circle:
            return nil
        case .dryBrush:
            return generateDryBrush()
        case .charcoal:
            return generateCharcoal()
        case .inkSplatter:
            return generateInkSplatter()
        case .grunge:
            return generateGrunge()
        case .flatBristle:
            return generateFlatBristle()
        case .crosshatch:
            return generateCrosshatch()
        }
    }

    // MARK: - Dry Brush (horizontal bristle streaks)

    private static func generateDryBrush() -> CGImage? {
        let size = tipSize
        var pixels = [UInt8](repeating: 0, count: size * size)
        var rng = LCGRandom(seed: 48271)

        // Create horizontal bristle bands
        let numBristles = 10 + Int(rng.nextFloat() * 5)
        var bristleBands: [(yStart: Int, height: Int, opacity: UInt8)] = []
        var y = 8
        for _ in 0..<numBristles {
            let h = 2 + Int(rng.nextFloat() * 5)
            let gap = 1 + Int(rng.nextFloat() * 3)
            let op = UInt8(160 + rng.nextFloat() * 95)
            bristleBands.append((yStart: y, height: h, opacity: op))
            y += h + gap
            if y >= size - 8 { break }
        }

        let cx = center
        let cy = center
        let r = radius - 4

        for band in bristleBands {
            for by in band.yStart..<min(band.yStart + band.height, size) {
                for bx in 0..<size {
                    let dx = CGFloat(bx) - cx
                    let dy = CGFloat(by) - cy
                    let dist = (dx * dx + dy * dy).squareRoot()
                    if dist > r { continue }

                    // Edge falloff
                    let edgeFactor = dist > r * 0.8 ? CGFloat(1.0 - (dist - r * 0.8) / (r * 0.2)) : 1.0

                    // Per-pixel noise for bristle texture
                    let noise = 0.6 + rng.nextFloat() * 0.4
                    let val = CGFloat(band.opacity) * edgeFactor * noise
                    pixels[by * size + bx] = UInt8(min(val, 255))
                }
            }
        }

        return makeGrayscaleImage(pixels: &pixels, width: size, height: size)
    }

    // MARK: - Charcoal (gaussian blob with noise)

    private static func generateCharcoal() -> CGImage? {
        let size = tipSize
        var pixels = [UInt8](repeating: 0, count: size * size)
        var rng = LCGRandom(seed: 65537)

        let cx = center
        let cy = center
        let sigma = radius * 0.45

        for y in 0..<size {
            for x in 0..<size {
                let dx = CGFloat(x) - cx
                let dy = CGFloat(y) - cy
                let dist2 = dx * dx + dy * dy

                // Gaussian falloff
                let gaussian = exp(-dist2 / (2 * sigma * sigma))

                // Heavy noise
                let noise = 0.25 + rng.nextFloat() * 0.75

                let val = gaussian * noise * 255
                pixels[y * size + x] = UInt8(min(max(val, 0), 255))
            }
        }

        return makeGrayscaleImage(pixels: &pixels, width: size, height: size)
    }

    // MARK: - Ink Splatter (solid with irregular edges)

    private static func generateInkSplatter() -> CGImage? {
        let size = tipSize
        var pixels = [UInt8](repeating: 0, count: size * size)
        var rng = LCGRandom(seed: 31337)

        let cx = center
        let cy = center
        let r = radius - 6

        // Generate edge perturbation table (angular noise)
        let numAngles = 64
        var edgeNoise = [CGFloat](repeating: 0, count: numAngles)
        for i in 0..<numAngles {
            edgeNoise[i] = 0.78 + rng.nextFloat() * 0.22
        }

        for y in 0..<size {
            for x in 0..<size {
                let dx = CGFloat(x) - cx
                let dy = CGFloat(y) - cy
                let dist = (dx * dx + dy * dy).squareRoot()

                // Look up edge radius for this angle
                let angle = atan2(dy, dx)
                let normAngle = (angle + .pi) / (2 * .pi)
                let idx = Int(normAngle * CGFloat(numAngles)) % numAngles
                let nextIdx = (idx + 1) % numAngles
                let frac = normAngle * CGFloat(numAngles) - CGFloat(idx)
                let edgeR = r * (edgeNoise[idx] * (1 - frac) + edgeNoise[nextIdx] * frac)

                if dist < edgeR * 0.85 {
                    pixels[y * size + x] = 255
                } else if dist < edgeR {
                    // Rough edge: random dropout
                    let edgeProbability = 1.0 - (dist - edgeR * 0.85) / (edgeR * 0.15)
                    if rng.nextFloat() < edgeProbability {
                        pixels[y * size + x] = UInt8(200 + rng.nextFloat() * 55)
                    }
                }
            }
        }

        // Add 4-7 small satellite dots
        let numDots = 4 + Int(rng.nextFloat() * 4)
        for _ in 0..<numDots {
            let angle = rng.nextFloat() * 2 * .pi
            let dist = r * (0.85 + rng.nextFloat() * 0.4)
            let dotCx = cx + cos(angle) * dist
            let dotCy = cy + sin(angle) * dist
            let dotR = 1.5 + rng.nextFloat() * 3
            for dy in Int(dotCy - dotR - 1)...Int(dotCy + dotR + 1) {
                for dx in Int(dotCx - dotR - 1)...Int(dotCx + dotR + 1) {
                    guard dx >= 0, dx < size, dy >= 0, dy < size else { continue }
                    let d = ((CGFloat(dx) - dotCx) * (CGFloat(dx) - dotCx) +
                             (CGFloat(dy) - dotCy) * (CGFloat(dy) - dotCy)).squareRoot()
                    if d <= dotR {
                        pixels[dy * size + dx] = UInt8(min(Int(pixels[dy * size + dx]) + 200, 255))
                    }
                }
            }
        }

        return makeGrayscaleImage(pixels: &pixels, width: size, height: size)
    }

    // MARK: - Grunge (random splotches)

    private static func generateGrunge() -> CGImage? {
        let size = tipSize
        var pixels = [UInt8](repeating: 0, count: size * size)
        var rng = LCGRandom(seed: 99991)

        let cx = center
        let cy = center
        let r = radius - 2

        // Place 20-30 random ellipses
        let numBlobs = 20 + Int(rng.nextFloat() * 10)
        for _ in 0..<numBlobs {
            let blobAngle = rng.nextFloat() * 2 * .pi
            let blobDist = rng.nextFloat() * r * 0.75
            let blobCx = cx + cos(blobAngle) * blobDist
            let blobCy = cy + sin(blobAngle) * blobDist
            let blobRx = 4 + rng.nextFloat() * 20
            let blobRy = 4 + rng.nextFloat() * 20
            let blobOp = UInt8(100 + rng.nextFloat() * 155)

            let minX = max(0, Int(blobCx - blobRx) - 1)
            let maxX = min(size - 1, Int(blobCx + blobRx) + 1)
            let minY = max(0, Int(blobCy - blobRy) - 1)
            let maxY = min(size - 1, Int(blobCy + blobRy) + 1)

            for y in minY...maxY {
                for x in minX...maxX {
                    let dx = (CGFloat(x) - blobCx) / blobRx
                    let dy = (CGFloat(y) - blobCy) / blobRy
                    if dx * dx + dy * dy <= 1.0 {
                        let existing = Int(pixels[y * size + x])
                        pixels[y * size + x] = UInt8(min(existing + Int(blobOp), 255))
                    }
                }
            }
        }

        // Add per-pixel noise
        for i in 0..<(size * size) {
            let noise = Int(rng.nextFloat() * 30)
            pixels[i] = UInt8(min(Int(pixels[i]) + noise, 255))
        }

        // Circular mask with soft falloff
        for y in 0..<size {
            for x in 0..<size {
                let dx = CGFloat(x) - cx
                let dy = CGFloat(y) - cy
                let dist = (dx * dx + dy * dy).squareRoot()
                if dist > r {
                    pixels[y * size + x] = 0
                } else if dist > r * 0.8 {
                    let fade = 1.0 - (dist - r * 0.8) / (r * 0.2)
                    pixels[y * size + x] = UInt8(CGFloat(pixels[y * size + x]) * fade)
                }
            }
        }

        return makeGrayscaleImage(pixels: &pixels, width: size, height: size)
    }

    // MARK: - Flat Bristle (rectangular with rough edges)

    private static func generateFlatBristle() -> CGImage? {
        let size = tipSize
        var pixels = [UInt8](repeating: 0, count: size * size)
        var rng = LCGRandom(seed: 77773)

        let rectLeft = 8
        let rectRight = size - 8
        let rectTop = size / 2 - 20
        let rectBottom = size / 2 + 20

        // Vertical bristle streaks
        let numStreaks = 12 + Int(rng.nextFloat() * 8)
        var streakPositions: [(x: Int, width: Int, opacity: UInt8)] = []
        var sx = rectLeft
        for _ in 0..<numStreaks {
            let w = 2 + Int(rng.nextFloat() * 6)
            let gap = Int(rng.nextFloat() * 2)
            let op = UInt8(160 + rng.nextFloat() * 95)
            streakPositions.append((x: sx, width: w, opacity: op))
            sx += w + gap
            if sx >= rectRight { break }
        }

        for streak in streakPositions {
            for x in streak.x..<min(streak.x + streak.width, rectRight) {
                for y in rectTop..<rectBottom {
                    // Top/bottom edge roughness
                    let distFromTop = y - rectTop
                    let distFromBottom = rectBottom - y
                    let edgeDist = min(distFromTop, distFromBottom)

                    var val = CGFloat(streak.opacity)

                    // Rough edges
                    if edgeDist < 5 {
                        let edgeFade = CGFloat(edgeDist) / 5.0
                        if rng.nextFloat() > edgeFade * 0.7 + 0.3 {
                            continue // skip pixel (rough edge)
                        }
                        val *= edgeFade
                    }

                    // Per-pixel noise
                    val *= 0.7 + rng.nextFloat() * 0.3

                    pixels[y * size + x] = UInt8(min(max(val, 0), 255))
                }
            }
        }

        return makeGrayscaleImage(pixels: &pixels, width: size, height: size)
    }

    // MARK: - Crosshatch (diagonal lines)

    private static func generateCrosshatch() -> CGImage? {
        let size = tipSize
        var pixels = [UInt8](repeating: 0, count: size * size)
        var rng = LCGRandom(seed: 54321)

        let cx = center
        let cy = center
        let r = radius - 4

        // Draw diagonal lines in two directions
        func drawLine(x0: CGFloat, y0: CGFloat, x1: CGFloat, y1: CGFloat,
                      width: CGFloat, opacity: UInt8) {
            let dx = x1 - x0
            let dy = y1 - y0
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0 else { return }
            let nx = -dy / length
            let ny = dx / length
            let steps = Int(length * 2)

            for s in 0...steps {
                let t = CGFloat(s) / CGFloat(steps)
                let px = x0 + dx * t
                let py = y0 + dy * t

                for w in stride(from: -width, through: width, by: 0.5) {
                    let fx = px + nx * w
                    let fy = py + ny * w
                    let ix = Int(fx)
                    let iy = Int(fy)
                    guard ix >= 0, ix < size, iy >= 0, iy < size else { continue }

                    let distFromCenter = abs(w) / width
                    let edgeFade = 1.0 - distFromCenter * distFromCenter
                    let val = Int(CGFloat(opacity) * edgeFade)
                    pixels[iy * size + ix] = UInt8(min(Int(pixels[iy * size + ix]) + val, 255))
                }
            }
        }

        // Upper-left to lower-right lines
        let numLines1 = 6 + Int(rng.nextFloat() * 4)
        for i in 0..<numLines1 {
            let offset = CGFloat(i) * CGFloat(size) / CGFloat(numLines1)
            let lineW: CGFloat = 1.5 + rng.nextFloat() * 2
            let op = UInt8(150 + rng.nextFloat() * 105)
            drawLine(x0: offset - 20, y0: 0, x1: offset + 20, y1: CGFloat(size),
                     width: lineW, opacity: op)
        }

        // Upper-right to lower-left lines
        let numLines2 = 4 + Int(rng.nextFloat() * 4)
        for i in 0..<numLines2 {
            let offset = CGFloat(i) * CGFloat(size) / CGFloat(numLines2)
            let lineW: CGFloat = 1.5 + rng.nextFloat() * 2
            let op = UInt8(120 + rng.nextFloat() * 105)
            drawLine(x0: CGFloat(size) - offset + 20, y0: 0,
                     x1: CGFloat(size) - offset - 20, y1: CGFloat(size),
                     width: lineW, opacity: op)
        }

        // Circular mask
        for y in 0..<size {
            for x in 0..<size {
                let dx = CGFloat(x) - cx
                let dy = CGFloat(y) - cy
                let dist = (dx * dx + dy * dy).squareRoot()
                if dist > r {
                    pixels[y * size + x] = 0
                } else if dist > r * 0.85 {
                    let fade = 1.0 - (dist - r * 0.85) / (r * 0.15)
                    pixels[y * size + x] = UInt8(CGFloat(pixels[y * size + x]) * fade)
                }
            }
        }

        return makeGrayscaleImage(pixels: &pixels, width: size, height: size)
    }

    // MARK: - Helpers

    private static func makeGrayscaleImage(pixels: inout [UInt8], width: Int, height: Int) -> CGImage? {
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil, shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

// MARK: - Seeded RNG

private struct LCGRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    mutating func nextFloat() -> CGFloat {
        return CGFloat(next() % 10000) / 10000.0
    }
}
