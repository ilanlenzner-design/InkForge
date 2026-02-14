import AppKit
import UniformTypeIdentifiers

class ExportManager {

    let canvasModel: CanvasModel

    init(canvasModel: CanvasModel) {
        self.canvasModel = canvasModel
    }

    enum ExportFormat {
        case png
        case jpeg(quality: CGFloat)
        case tiff

        var fileExtension: String {
            switch self {
            case .png:  return "png"
            case .jpeg: return "jpg"
            case .tiff: return "tiff"
            }
        }

        var utType: UTType {
            switch self {
            case .png:  return .png
            case .jpeg: return .jpeg
            case .tiff: return .tiff
            }
        }
    }

    func exportImage(format: ExportFormat, from window: NSWindow) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = "InkForge Drawing.\(format.fileExtension)"

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.writeImage(to: url, format: format)
        }
    }

    private func writeImage(to url: URL, format: ExportFormat) {
        guard let composite = canvasModel.layerStack.compositeImage() else { return }

        let bitmapRep = NSBitmapImageRep(cgImage: composite)
        let data: Data?

        switch format {
        case .png:
            data = bitmapRep.representation(using: .png, properties: [:])
        case .jpeg(let quality):
            data = bitmapRep.representation(using: .jpeg,
                properties: [.compressionFactor: quality])
        case .tiff:
            data = bitmapRep.representation(using: .tiff,
                properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw])
        }

        try? data?.write(to: url)
    }
}
