import Foundation
import CoreGraphics

class GeminiProvider: AIProvider {

    let name = "Gemini"
    let supportedModes: [AIMode] = [
        .generate, .referencePose,
        .styleTransfer, .sketchToPainting, .autoColor, .lineArt, .upscale, .bgRemove,
        .inpaint, .textureFill, .outpaint,
        .describe, .variations, .objectSelect,
    ]

    private var currentTask: URLSessionDataTask?

    func process(_ request: AIRequest,
                 progress: @escaping (Double) -> Void,
                 completion: @escaping (Result<AIResponse, AIError>) -> Void) {

        guard let apiKey = AIProviderManager.shared.apiKey(for: name) else {
            completion(.failure(.noAPIKey))
            return
        }

        let model: String
        let wantsImage: Bool

        switch request.mode {
        case .describe:
            model = "gemini-2.5-flash"
            wantsImage = false
        default:
            model = "gemini-3-pro-image-preview"
            wantsImage = true
        }

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        guard let url = URL(string: urlString) else {
            completion(.failure(.networkError("Invalid URL")))
            return
        }

        let body = buildRequestBody(request: request, wantsImage: wantsImage)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.timeoutInterval = 120

        do {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(.networkError("Failed to encode request: \(error.localizedDescription)")))
            return
        }

        progress(0.1)

        let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if let error = error as NSError? {
                if error.code == NSURLErrorCancelled {
                    completion(.failure(.cancelled))
                } else {
                    completion(.failure(.networkError(error.localizedDescription)))
                }
                return
            }

            guard let data = data else {
                completion(.failure(.invalidResponse))
                return
            }

            progress(0.8)

            do {
                let result = try self.parseResponse(data: data, wantsImage: wantsImage)
                progress(1.0)
                completion(.success(result))
            } catch let aiError as AIError {
                completion(.failure(aiError))
            } catch {
                completion(.failure(.providerError(error.localizedDescription)))
            }
        }

        currentTask = task
        task.resume()
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Request Building

    private func buildRequestBody(request: AIRequest, wantsImage: Bool) -> [String: Any] {
        var parts: [[String: Any]] = []

        // For inpaint with mask: blank out the selected area so the AI sees a "hole" to fill
        if request.mode == .inpaint, let image = request.inputImage, let mask = request.maskImage {
            let blanked = Self.blankMaskedArea(image: image, mask: mask)
            if let base64 = ImageConverter.cgImageToBase64(blanked ?? image) {
                parts.append([
                    "inlineData": [
                        "mimeType": "image/png",
                        "data": base64,
                    ]
                ])
            }
        } else if request.mode.needsInputImage,
                  let image = request.inputImage,
                  let base64 = ImageConverter.cgImageToBase64(image) {
            parts.append([
                "inlineData": [
                    "mimeType": "image/png",
                    "data": base64,
                ]
            ])
        }

        // Build prompt text based on mode
        let promptText: String
        switch request.mode {
        case .generate:
            promptText = "Generate an image: \(request.prompt). Output the image at \(request.width)x\(request.height) resolution."
        case .referencePose:
            promptText = "Generate a clean figure drawing reference pose: \(request.prompt). Simple neutral background, clear anatomical proportions. Output as an image."
        case .styleTransfer:
            promptText = "Apply this style to the image: \(request.prompt). Keep the content but change the artistic style. Output as an image."
        case .sketchToPainting:
            promptText = "Convert this sketch into a detailed, polished painting in this style: \(request.prompt). Keep the composition and subjects from the sketch but render them as a finished painting. Output as an image."
        case .autoColor:
            promptText = "Colorize this line art or sketch with these colors/theme: \(request.prompt). Keep all the lines and details, only add color. Output as an image."
        case .lineArt:
            promptText = "Extract clean black line art from this image. Output only the outlines and edges as black lines on a pure white background. No color, no shading, just clean linework. Output as an image."
        case .upscale:
            promptText = "Upscale and enhance this image. Add more detail and sharpness while preserving the original content exactly. Output as a high-quality image."
        case .bgRemove:
            promptText = "Remove the background from this image. Keep only the main subject(s). Replace the background with solid pure white. Output as an image."
        case .inpaint:
            if request.maskImage != nil {
                promptText = "This image has a blank white area. Fill in ONLY the blank white area with: \(request.prompt). Keep everything outside the blank area exactly the same. Output the complete image."
            } else {
                promptText = "Edit this image: \(request.prompt). Output the edited image."
            }
        case .textureFill:
            promptText = "Generate a seamless tileable texture pattern of: \(request.prompt). The texture should tile seamlessly in all directions. Output as an image at \(request.width)x\(request.height) resolution."
        case .outpaint:
            promptText = "This image is a cropped portion of a larger scene. Naturally extend and expand the image content beyond its current edges. Context for what lies beyond: \(request.prompt). Keep the existing content in the center unchanged and seamlessly extend the scene. Output as an image."
        case .describe:
            promptText = request.prompt.isEmpty ? "Describe this image in detail." : request.prompt
        case .variations:
            let extra = request.prompt.isEmpty ? "" : " Variation direction: \(request.prompt)."
            promptText = "Create an artistic variation of this image. Keep the same general subject and composition but change the style, colors, or mood.\(extra) Output as an image."
        case .objectSelect:
            promptText = "Create a black and white segmentation mask for this image. Make the following object pure white: \(request.prompt). Make everything else pure black. Output only the mask as an image — no other content."
        }

        parts.append(["text": promptText])

        var body: [String: Any] = [
            "contents": [
                ["parts": parts]
            ]
        ]

        // Request image output for non-describe modes
        if wantsImage {
            body["generationConfig"] = [
                "responseModalities": ["TEXT", "IMAGE"]
            ]
        }

        return body
    }

    // MARK: - Inpaint Masking

    /// Fills the selected (white) areas of the mask with solid white on the image,
    /// creating a visible "hole" for the AI to fill in.
    private static func blankMaskedArea(image: CGImage, mask: CGImage) -> CGImage? {
        let w = image.width
        let h = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let rect = CGRect(x: 0, y: 0, width: w, height: h)

        // Draw the original image
        ctx.draw(image, in: rect)

        // Clip to the selection mask (white=selected) and fill with white
        ctx.saveGState()
        ctx.clip(to: rect, mask: mask)
        ctx.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        ctx.fill(rect)
        ctx.restoreGState()

        return ctx.makeImage()
    }

    // MARK: - Response Parsing

    private func parseResponse(data: Data, wantsImage: Bool) throws -> AIResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.invalidResponse
        }

        // Check for API error
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw AIError.providerError(message)
        }

        guard let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw AIError.invalidResponse
        }

        var resultImage: CGImage?
        var resultText: String?

        for part in parts {
            // Check for inline image data
            if let inlineData = part["inlineData"] as? [String: Any],
               let base64Data = inlineData["data"] as? String {
                resultImage = ImageConverter.base64ToCGImage(base64Data)
            }
            // Check for text
            if let text = part["text"] as? String {
                resultText = text
            }
        }

        if wantsImage && resultImage == nil && resultText != nil {
            // Model returned text instead of image — report it
            throw AIError.providerError("Model returned text instead of image: \(resultText!.prefix(200))")
        }

        return AIResponse(resultImage: resultImage, text: resultText)
    }

}
