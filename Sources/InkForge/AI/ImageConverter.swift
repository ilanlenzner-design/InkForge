import AppKit
import CoreGraphics
import ImageIO

enum ImageConverter {

    static func cgImageToPNGData(_ image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    static func cgImageToBase64(_ image: CGImage) -> String? {
        guard let data = cgImageToPNGData(image) else { return nil }
        return data.base64EncodedString()
    }

    static func base64ToCGImage(_ base64: String) -> CGImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return dataToCGImage(data)
    }

    static func dataToCGImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func selectionMaskToPNGData(maskImage: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: maskImage)
        return rep.representation(using: .png, properties: [:])
    }
}
