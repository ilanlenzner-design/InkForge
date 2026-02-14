import Foundation
import CoreGraphics

enum AIMode: String, CaseIterable {
    case generate
    case styleTransfer
    case inpaint
    case describe

    var displayName: String {
        switch self {
        case .generate:      return "Generate"
        case .styleTransfer: return "Style Transfer"
        case .inpaint:       return "Inpaint"
        case .describe:      return "Describe"
        }
    }

    var promptPlaceholder: String {
        switch self {
        case .generate:      return "Describe the image to generate..."
        case .styleTransfer: return "Describe the style to apply..."
        case .inpaint:       return "Describe what to fill in the selected area..."
        case .describe:      return "Ask about the image..."
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
        case .noAPIKey:             return "No API key configured. Open Settings to add one."
        case .networkError(let msg): return "Network error: \(msg)"
        case .providerError(let msg): return "Provider error: \(msg)"
        case .timeout:              return "Request timed out."
        case .cancelled:            return "Request was cancelled."
        case .invalidResponse:      return "Invalid response from provider."
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
