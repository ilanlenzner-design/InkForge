import Foundation
import CoreGraphics

class CanvasSnapshot {
    let layerIndex: Int
    let image: CGImage
    let maskImage: CGImage?
    let textContent: TextContent?

    init(layerIndex: Int, image: CGImage, maskImage: CGImage? = nil,
         textContent: TextContent? = nil) {
        self.layerIndex = layerIndex
        self.image = image
        self.maskImage = maskImage
        self.textContent = textContent
    }
}
