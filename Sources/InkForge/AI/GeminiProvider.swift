import Foundation
import CoreGraphics

class GeminiProvider: AIProvider {

    let name = "Gemini"
    let supportedModes: [AIMode] = [.generate, .styleTransfer, .inpaint, .describe]

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
        case .generate, .styleTransfer, .inpaint:
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
        } else if let image = request.inputImage, let base64 = ImageConverter.cgImageToBase64(image) {
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
        case .styleTransfer:
            promptText = "Apply this style to the image: \(request.prompt). Keep the content but change the artistic style. Output as an image."
        case .inpaint:
            if request.maskImage != nil {
                promptText = "This image has a blank white area. Fill in ONLY the blank white area with: \(request.prompt). Keep everything outside the blank area exactly the same. Output the complete image."
            } else {
                promptText = "Edit this image: \(request.prompt). Output the edited image."
            }
        case .describe:
            promptText = request.prompt.isEmpty ? "Describe this image in detail." : request.prompt
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
