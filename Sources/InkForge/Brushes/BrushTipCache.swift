import CoreGraphics
import Foundation

class BrushTipCache {

    static let shared = BrushTipCache()

    private var cache: [BrushPreset.BrushTipType: CGImage] = [:]
    private let lock = NSLock()

    private init() {}

    func tipImage(for tipType: BrushPreset.BrushTipType) -> CGImage? {
        if tipType == .circle { return nil }

        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[tipType] { return cached }

        guard let image = BrushTipGenerator.generate(tipType) else { return nil }
        cache[tipType] = image
        return image
    }

    func purge() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}
