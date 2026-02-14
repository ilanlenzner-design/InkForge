import Foundation
import CoreGraphics

enum AIMode: String, CaseIterable {
    // Generation
    case generate
    case referencePose
    // Transform
    case styleTransfer
    case sketchToPainting
    case autoColor
    case lineArt
    case upscale
    case bgRemove
    // Selection-based
    case inpaint
    case textureFill
    case outpaint
    // Analyze
    case describe
    case variations
    case objectSelect

    var displayName: String {
        switch self {
        case .generate:         return "Generate Image"
        case .referencePose:    return "Reference Pose"
        case .styleTransfer:    return "Style Transfer"
        case .sketchToPainting: return "Sketch to Painting"
        case .autoColor:        return "Auto-Color"
        case .lineArt:          return "Line Art Extract"
        case .upscale:          return "Upscale"
        case .bgRemove:         return "Background Remove"
        case .inpaint:          return "Inpaint"
        case .textureFill:      return "Texture Fill"
        case .outpaint:         return "Outpaint"
        case .describe:         return "Describe"
        case .variations:       return "Variations"
        case .objectSelect:     return "Object Select"
        }
    }

    var group: String {
        switch self {
        case .generate, .referencePose:
            return "Generate"
        case .styleTransfer, .sketchToPainting, .autoColor, .lineArt, .upscale, .bgRemove:
            return "Transform"
        case .inpaint, .textureFill, .outpaint:
            return "Selection"
        case .describe, .variations, .objectSelect:
            return "Analyze"
        }
    }

    var needsInputImage: Bool {
        switch self {
        case .generate, .referencePose, .textureFill:
            return false
        default:
            return true
        }
    }

    var needsPrompt: Bool {
        switch self {
        case .lineArt, .upscale, .bgRemove:
            return false
        default:
            return true
        }
    }

    var promptPlaceholder: String {
        switch self {
        case .generate:         return "Describe the image to generate..."
        case .referencePose:    return "Describe the pose (e.g. 'sitting cross-legged')..."
        case .styleTransfer:    return "Describe the style to apply..."
        case .sketchToPainting: return "Describe the painting style..."
        case .autoColor:        return "Describe the colors to use..."
        case .lineArt:          return "(no prompt needed)"
        case .upscale:          return "(no prompt needed)"
        case .bgRemove:         return "(no prompt needed)"
        case .inpaint:          return "Describe what to fill in the selected area..."
        case .textureFill:      return "Describe the texture (e.g. 'mossy stone wall')..."
        case .outpaint:         return "Describe what's beyond the edges..."
        case .describe:         return "Ask about the image (or leave blank)..."
        case .variations:       return "Optionally describe how to vary it..."
        case .objectSelect:     return "Describe the object to select..."
        }
    }

    var infoHint: String? {
        switch self {
        case .generate:         return "Creates a new layer with the generated image."
        case .referencePose:    return "Creates a reference pose on a new layer."
        case .bgRemove:         return "Isolates the subject on a new layer."
        case .lineArt:          return "Extracts line art onto a new layer."
        case .upscale:          return "Enhances detail and clarity on a new layer."
        case .objectSelect:     return "Creates a selection from the AI result."
        case .variations:       return "Generates a variation on a new layer."
        case .outpaint:         return "Extends the artwork beyond current edges."
        case .sketchToPainting: return "Converts sketch to painting on a new layer."
        default:                return nil  // dynamic hints handled by the sheet
        }
    }

    /// True if this mode produces a selection mask instead of a layer.
    var producesSelectionMask: Bool {
        return self == .objectSelect
    }

    /// Ordered groups for UI display.
    static var groupedModes: [(group: String, modes: [AIMode])] {
        let order = ["Generate", "Transform", "Selection", "Analyze"]
        return order.compactMap { group in
            let modes = AIMode.allCases.filter { $0.group == group }
            return modes.isEmpty ? nil : (group: group, modes: modes)
        }
    }
}

struct AIRequest {
    let mode: AIMode
    let prompt: String
    let inputImage: CGImage?
    let maskImage: CGImage?
    let width: Int
    let height: Int
}

struct AIResponse {
    let resultImage: CGImage?
    let text: String?
}

enum AIError: Error, LocalizedError {
    case noAPIKey
    case networkError(String)
    case providerError(String)
    case timeout
    case cancelled
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey:              return "No API key configured. Open Settings to add one."
        case .networkError(let msg): return "Network error: \(msg)"
        case .providerError(let msg): return "Provider error: \(msg)"
        case .timeout:               return "Request timed out."
        case .cancelled:             return "Request was cancelled."
        case .invalidResponse:       return "Invalid response from provider."
        }
    }
}

protocol AIProvider {
    var name: String { get }
    var supportedModes: [AIMode] { get }
    func process(_ request: AIRequest,
                 progress: @escaping (Double) -> Void,
                 completion: @escaping (Result<AIResponse, AIError>) -> Void)
    func cancel()
}
